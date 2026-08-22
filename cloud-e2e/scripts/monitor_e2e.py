"""One ~9.5-min watch window for a cloud-pipeline E2E leg.

Usage: monitor_e2e.py <partner> <session> <t0_ms> [edl|finish]

Exit: 0 = leg done (edl mode: status edl_ready/complete or previewReady flag;
finish mode: a `_workflow/finish.<executionId>.done.json` marker newer than
T0), 1 = a step failed since T0, 3 = window elapsed (re-arm the SAME command;
a full leg normally needs 4-6 windows).

Run it as a BACKGROUND task — one window is ~9.5 min of polling.
"""
import datetime as dt
import json
import subprocess
import sys
import time

REPO = "/Users/llwire/src/projects/infinit-studio"
sys.path.insert(0, f"{REPO}/orchestrator")

if len(sys.argv) < 4:
    raise SystemExit("usage: monitor_e2e.py <partner> <session> <t0_ms> [edl|finish]")
CREATOR, SESSION = sys.argv[1], sys.argv[2]
T0 = dt.datetime.fromtimestamp(int(sys.argv[3]) / 1000, dt.timezone.utc)
MODE = sys.argv[4] if len(sys.argv) > 4 else "edl"
DEADLINE = time.time() + 9.5 * 60

from cloud.session_transfer import list_session_r2, read_file_r2  # noqa: E402


def fresh_done_marker():
    try:
        keys = list_session_r2(CREATOR, SESSION, prefix="_workflow/")
    except Exception:
        return None
    for k in [str(x) for x in (keys if not isinstance(keys, dict) else keys)]:
        base = k.split("/")[-1]
        if base.startswith("finish.") and base.endswith(".done.json"):
            try:
                raw = read_file_r2(CREATOR, SESSION, f"_workflow/{base}")
                doc = json.loads(raw.decode() if isinstance(raw, bytes) else raw)
                if dt.datetime.fromisoformat(doc["finished_at"]) >= T0:
                    return base
            except Exception:
                continue
    return None


def doc_state():
    out = subprocess.run(
        [f"{REPO}/orchestrator/venv/bin/python", "-c", (
            "import json,sys;"
            f"sys.path.insert(0,'{REPO}/orchestrator');"
            "from cloud.status import read_session_doc;"
            f"d=read_session_doc('{CREATOR}','{SESSION}');"
            "print(json.dumps({'status':d.get('status'),"
            "'previewReady':d.get('previewReady'),"
            "'steps':d.get('steps',{})},default=str))")],
        capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        return {}
    return json.loads(out.stdout.strip() or "{}")


while time.time() < DEADLINE:
    if MODE == "finish":
        hit = fresh_done_marker()
        if hit:
            print(f"DONE-MARKER: {hit}")
            sys.exit(0)
    d = doc_state()
    # Step dicts MERGE on write, so a step's stale `error`/`seconds` keys ride
    # along on newer `running` writes. `at` is an EPOCH-MS STRING. Only steps
    # stamped at/after T0 belong to this run.
    fresh = {}
    for name, s in (d.get("steps") or {}).items():
        try:
            ts = dt.datetime.fromtimestamp(float(s.get("at", 0)) / 1000,
                                           dt.timezone.utc)
        except (TypeError, ValueError):
            continue
        if ts >= T0:
            fresh[name] = s.get("status")
    print(f"[{dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')}] "
          f"status={d.get('status')} previewReady={d.get('previewReady')} "
          f"{json.dumps(dict(sorted(fresh.items())))}", flush=True)
    if MODE == "edl" and (d.get("status") in ("edl_ready", "complete")
                          or d.get("previewReady") is True):
        print("PREVIEW READY")
        sys.exit(0)
    failed = [n for n, v in fresh.items() if v == "failed"]
    if failed or d.get("status") == "failed":
        print(f"FAILED: {failed} status={d.get('status')}")
        sys.exit(1)
    time.sleep(45)
print("STILL-RUNNING (window elapsed)")
sys.exit(3)
