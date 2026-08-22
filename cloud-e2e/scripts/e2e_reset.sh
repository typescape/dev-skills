#!/bin/bash
# E2E RESET (no fire) — infinit-studio cloud pipeline.
#
#   e2e_reset.sh <partner> <session>
#   e2e_reset.sh anraga session_1776282026295
#
# Owner ritual (R14 pattern, generalized from scratch/e2e_anraga_406.sh):
#   R2  -> MASTERS-ONLY. Everything else is deleted, INCLUDING render/
#          deliverables and any archive-restored color artifacts — fresh
#          derivation from raw footage is the whole point of an E2E.
#   GCS -> confirmed empty (zero-GCS baseline; #404 R2 is the store of record).
#   Firestore session doc -> deleted, restamped upload_complete, cameraCount
#          written as a real INTEGER (the workflow reads .integerValue; an
#          untyped string from `cloud.status --set` KeyErrors the run).
#   pipeline_actions start doc -> deleted (a delete raises no Eventarc event).
#
# Does NOT fire. The caller fires leg 1 explicitly (see SKILL.md) so the
# code_ref is a conscious choice every single time.
set -euo pipefail

P="${1:?usage: e2e_reset.sh <partner> <session>}"
S="${2:?usage: e2e_reset.sh <partner> <session>}"
PROJECT=infinit-partner
REPO="/Users/llwire/src/projects/infinit-studio"
cd "$REPO"

CAMFILE="$(mktemp)"
trap 'rm -f "$CAMFILE"' EXIT

# ── 0/4 preflight: resolve the admin shared secret BEFORE anything destructive.
# Step 3's `cloud.status --with-preview-token` needs it, and status.py reads it
# from config/secrets.json ONLY. An empty secrets.json therefore used to fail the
# restamp AFTER the session doc was already deleted — leaving a deleted-but-
# unrestamped session that looks fine until leg 1 fires at a doc that no longer
# exists. Resolve it here (secrets.json, else the ejson) and abort while the
# session is still intact. The VALUE is never printed — only its source.
if [ -z "${ADMIN_SHARED_SECRET:-}" ]; then
    ADMIN_SHARED_SECRET="$(orchestrator/venv/bin/python - <<'PYEOF' || true
import json, pathlib, subprocess, sys

cfg = pathlib.Path("orchestrator/config")


def _dig(blob):
    try:
        return ((json.loads(blob).get("frameio") or {}).get("adminSecret") or "")
    except Exception:
        return ""


secret = ""
plain = cfg / "secrets.json"
if plain.is_file() and plain.stat().st_size:
    secret = _dig(plain.read_text())
    if secret:
        print("secrets.json", file=sys.stderr)
if not secret and (cfg / "secrets.ejson").is_file():
    try:
        out = subprocess.run(["ejson", "decrypt", str(cfg / "secrets.ejson")],
                             capture_output=True, text=True, check=True).stdout
        secret = _dig(out)
        if secret:
            print("secrets.ejson (secrets.json empty or lacking the key)",
                  file=sys.stderr)
    except Exception:
        pass
print(secret)
PYEOF
    )"
fi
if [ -z "${ADMIN_SHARED_SECRET:-}" ]; then
    echo "ABORT: no admin shared secret — set ADMIN_SHARED_SECRET, or restore" \
         "frameio.adminSecret in orchestrator/config/secrets.json (it is" \
         "regenerable: ejson decrypt orchestrator/config/secrets.ejson)." \
         "NOTHING has been reset; the session is untouched." >&2
    exit 2
fi
export ADMIN_SHARED_SECRET
echo "── 0/4 admin secret resolved (len ${#ADMIN_SHARED_SECRET}) — safe to reset ──"

echo "── 1/4 R2 → masters-only (verify keeps FIRST) ── $P/$S"
orchestrator/venv/bin/python - "$P" "$S" "$CAMFILE" <<'PYEOF'
import json, re, subprocess, sys

partner, session, camfile = sys.argv[1:4]
sec = json.loads(subprocess.run(
    ["ejson", "decrypt", "orchestrator/config/secrets.ejson"],
    capture_output=True, text=True, check=True).stdout)
r2 = sec["cloudflare"]["r2"]
import boto3
s3 = boto3.client("s3", endpoint_url=r2["s3BaseUrl"],
                  aws_access_key_id=r2["accessKeyId"],
                  aws_secret_access_key=r2["secretAccessKey"])
NS = f"{partner}/{session}"


def all_keys():
    token, out = None, []
    while True:
        kw = {"Bucket": "infinit-studio", "Prefix": NS + "/"}
        if token:
            kw["ContinuationToken"] = token
        resp = s3.list_objects_v2(**kw)
        out += [o["Key"] for o in resp.get("Contents", [])]
        if not resp.get("IsTruncated"):
            return out
        token = resp.get("NextContinuationToken")


keys = all_keys()
# Masters only: cameras/camera_<n>.<mp4|mov>. Proxies (camera_0.preview.mp4)
# and every derived artifact are deliberately NOT kept. Some partners shoot
# .mov — never filter camera listings to .mp4 alone.
master_re = re.compile(rf"^{re.escape(NS)}/cameras/camera_\d+\.(mp4|mov)$", re.I)
KEEP = sorted(k for k in keys if master_re.match(k))
if not KEEP:
    raise SystemExit(f"ABORT: no masters under {NS}/cameras/ — refusing to wipe")
for k in KEEP:
    s3.head_object(Bucket="infinit-studio", Key=k)  # raises if absent
    print("  keep:", k)
print("masters verified present:", len(KEEP))

batch = [k for k in keys if k not in set(KEEP)]
for i in range(0, len(batch), 1000):
    s3.delete_objects(Bucket="infinit-studio", Delete={
        "Objects": [{"Key": k} for k in batch[i:i + 1000]], "Quiet": True})
print(f"r2: deleted {len(batch)} objects; masters-only remains")
open(camfile, "w").write(str(len(KEEP)))
PYEOF
CAMERA_COUNT="$(cat "$CAMFILE")"

echo "── 2/4 GCS: confirm session prefix empty ──"
# `gcloud storage ls '**'` EXITS 1 on an empty prefix — the || true keeps
# pipefail from killing the reset (E2E-R14 gotcha).
CNT=$( (gcloud storage ls "gs://infinit-studio/$P/$S/**" --project=$PROJECT 2>/dev/null || true) | wc -l | tr -d ' ')
if [ "$CNT" != "0" ]; then
  echo "GCS NOT empty ($CNT objects) — deleting (zero-GCS baseline)"
  gcloud storage rm -r "gs://infinit-studio/$P/$S/" --project=$PROJECT 2>&1 | tail -1
else
  echo "GCS empty ✓ (zero-GCS baseline holds)"
fi

echo "── 3/4 Firestore session doc: delete + restamp upload_complete ──"
cd "$REPO/orchestrator"
GOOGLE_APPLICATION_CREDENTIALS=config/service_account.json venv/bin/python - "$P" "$S" <<'PYEOF'
import sys
from google.cloud import firestore
partner, session = sys.argv[1:3]
firestore.Client(project="infinit-partner").collection("sessions").document(
    f"{partner}__{session}").delete()
print("session doc deleted")
PYEOF
GOOGLE_APPLICATION_CREDENTIALS=config/service_account.json venv/bin/python -m cloud.status \
  "$P/$S" --set status=upload_complete ingestMode=studio --with-preview-token
# cameraCount must be a Firestore INTEGER (workflow reads .integerValue);
# `cloud.status --set` writes untyped strings, so stamp it via the client.
GOOGLE_APPLICATION_CREDENTIALS=config/service_account.json venv/bin/python - "$P" "$S" "$CAMERA_COUNT" <<'PYEOF'
import sys
from google.cloud import firestore
partner, session, count = sys.argv[1:4]
firestore.Client(project="infinit-partner").collection("sessions").document(
    f"{partner}__{session}").set({"cameraCount": int(count)}, merge=True)
print(f"cameraCount stamped as int: {count}")
PYEOF

echo "── 4/4 action doc: delete (no event) ──"
GOOGLE_APPLICATION_CREDENTIALS=config/service_account.json venv/bin/python - "$P" "$S" <<'PYEOF'
import sys
from google.cloud import firestore
partner, session = sys.argv[1:3]
firestore.Client(project="infinit-partner").collection(
    "pipeline_actions").document(f"{partner}__{session}").delete()
print("action doc deleted (delete raises no event)")
PYEOF
cd "$REPO"

echo "RESET COMPLETE for $P/$S ($CAMERA_COUNT cameras) — no fire."
echo "Leg 1 fire is a separate, deliberate step (see the cloud-e2e skill)."
