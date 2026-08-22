# cloud-e2e reference

Detail behind [SKILL.md](SKILL.md). Every gotcha below cost a real debugging session.

## Gotchas

**code_ref.** The worker checkout rejects short shas — always the full 40 chars from
`git rev-parse "<ref>^{commit}"`. Assembly honors the workflow's `${code_ref}` only since
commit cb00f66; older revisions silently ran `cloud-stable`, so a "PR validation" could produce
an EDL from entirely different code. Pre-merge runs pass the same sha to BOTH legs. The
production action-doc path hardcodes `cloud-stable` in `session_to_edl.yaml`, by design.

**Firestore step reads.** `at` stamps are **epoch-ms strings** — `datetime.fromisoformat` throws
on every one of them and a naive filter silently skips all steps, showing an empty run. Step dicts
also **merge** on write, so stale `error`/`seconds` keys ride along on a newer `running` write.
Always filter steps by `at >= T0` and read `status`+`at` only; never trust absolute step state.

**fps.** NEVER assume 25 fps. Read it from the render with `ffprobe` or from the EDL before any
frame↔time math. anraga sources are 30 fps; a 25 fps assumption once put a seam scan 4 minutes
off target.

**Idle-looking workers.** Under GitHub degradation a worker's code checkout can take 15+ minutes
while the pod reports "running" with nothing executing. That is not wedged — read the worker log
for checkout progress before declaring a failure or killing the run.

**Step flips lag the jobs.** A step can show completed while its RunPod job is still IN_PROGRESS
(and vice versa). Read `executionTime`/`exec_s` from the job payload for real lane durations.

**preview_ready is terminal for leg 1.** Since the approval trigger shipped (7af10af), the v1
auto-chain is gone. If you are waiting for a render after preview_ready with no finish action
fired, you will wait forever.

**Eventarc is CREATED-only.** Updating an existing action doc raises no event. The ms suffix in
`<partner>__<session>__<epoch-ms>` is what guarantees each emit is a create.
`<partner>__<session>__finish__<ms>` is the finish verb; ULID session ids never contain `__`,
so the parse is safe.

**cameraCount must be an int.** `cloud.status --set` writes untyped strings; the workflow reads
`.integerValue` and KeyErrors on `'2'`. `e2e_reset.sh` stamps it through the Firestore client.

**`gcloud storage ls '**'` exits 1 on an empty prefix** — under `set -euo pipefail` that kills the
reset right after the R2 wipe. The reset script `|| true`s it.

**Reset wipes the color artifacts too.** That is the point (fresh derivation), but it means a
masters-only reset once wiped `camera_sync`'s stamp and produced a one-camera color recipe →
camera 1 rendered ungraded. Fixed at d1912cb (R2 listing is authoritative for the camera set under
cloud assembly). Since the render is no longer pulled locally, catch this class from the
artifacts instead: confirm `color_recipe.json` covers BOTH cameras after the reset, and flag it
for the owner's review-app eyeball if it doesn't.

## Smoke-render gotchas

**Pipeline runs go to an external Terminal, always.** Never the agent's Bash tool — the owner
follows the run live. Terminal runs **x86_64** against a universal2 venv with arm64-only numpy, so
the wrapper must invoke `arch -arm64 venv/bin/python`. (The Bash tool itself runs arm64 natively —
unit tests there are fine.) `smoke_regen.sh` writes the wrapper and `open -a Terminal`s it; the rc
comes back through `<session_dir>/.regen_done`, which is what you poll.

**Regen on a COPY.** `scratch/<purpose>_smoke/<partner>/<session>`, never `/Volumes/Studio`
(`smoke_regen.sh` aborts on a `/Volumes` path). If the pipeline demands camera masters locally,
symlink `cameras/` rather than copying ~10 GB.

**`ARTIFACT_CHECKS=warn`.** The staleness preflight (#331) blocks a regen on an older pulled copy.
`warn` downgrades it, which is correct for a smoke — the goal is mechanism validation, not a
bit-exact plan. Do not reach for it on an E2E.

**The N-minute window must contain the feature seams.** Truncation keeps whole rows ending inside
the window plus the `is_break_region` rows; nothing is recomputed. Read `edl_truncate.py`'s row
table and confirm the seam of interest is inside **before** the push. An empty window renders a
clean, useless video at full price.

**R2 `edl.json` pushes are owner-run.** Consistently permission-blocked for the agent. Write the
command out, hand it over, wait for "pushed". Use `push_file_r2` (it stamps Content-Type per #404),
not a raw boto3 put.

**Restore the EDL, or the next run renders 3 minutes.** A smoke leaves the truncated EDL as the
session's R2 `edl.json`. Nothing downstream flags this — the next full render, E2E, or owner review
just silently gets the stump. Restoring is part of the smoke, not a follow-up.

**`--max-cuts N` is the other truncation.** `cloud_render_submit.sh --max-cuts N` sets
`RENDER_ENGINE_MAX_CUTS` on the worker: first N cuts, output `<stem>.smoke.mp4`, EDL in R2
untouched. Cheaper on ceremony — no push, no restore — but cuts ≠ minutes and you cannot aim it at
a specific seam. Use it when any early seam will do; truncate the EDL when a particular one must be
in frame.

**The submit re-claims the session doc.** `cloud_render_submit.sh` writes a fresh `executionId`
before POSTing, because the worker's zombie fence compares it against the payload — an unclaimed
job skips every runnable "cleanly" (rc 0, nothing rendered). Consequence: never smoke a session
that has a run in flight; the claim stomp fences the other one.

**A smoke proves nothing about the cloud EDL leg.** That code never runs. If the EDL leg is what
changed, only an E2E answers the question.

## Cost and time bands

| Leg | Wall | Cost |
|---|---|---|
| EDL (fire → preview_ready) | T+27-45 min | ~$0.9 compute + ~$1.3 LLM |
| Render (fire → done marker) | ~35-40 min | ~$1.0-1.4 |
| All-in | ~60-90 min | ~$3.4 |
| Smoke render (submit → done marker, first ~3 min of program) | ~10-15 min | ~$0.10-0.30 |

Compute cost = GPU seconds × the class rate from `_DEFAULT_RATES` in
`orchestrator/cloud/runpod_worker.py` — the **single source of truth** (the env override
`RUNPOD_RATES_JSON` is deliberately emptied to `{}`). Rates are VRAM-class tiers: MIG slices bill
their class rate, and the MIG profile in the device name ("MIG 2g.48gb") is authoritative for
attribution over any parent-card name.

Reference points: render throughput ladder 11.5 fps (A40 baseline) → 18.0 (A40 fast path) → 36.5
(L40S + NVENC + tetra kernel) → 50.0 (PRO 6000 Blackwell MIG). Perception is host-lottery: the
same lane has measured 12 min and 22 min on different hosts with no cold-start component.

## R2 access pattern

Always from the orchestrator dir, with its venv:

```bash
cd /Users/llwire/src/projects/infinit-studio/orchestrator && venv/bin/python -c "
import sys; sys.path.insert(0, '.')
from cloud.session_transfer import read_file_r2, list_session_r2
print(list_session_r2('<partner>', '<session>', prefix='render/'))"
```

`read_file_r2` buffers in memory — small files only (`edl.json`, manifests, `.timing.json`).

**Never download the render mp4.** It is multi-GB, the owner reviews it in the Infinit UI and can
fetch it themselves, and pulling it locally buys nothing the `.timing.json` numbers don't already
prove. Report its key and size instead — a listing gives both without transferring bytes:

```bash
cd /Users/llwire/src/projects/infinit-studio/orchestrator && venv/bin/python -c "
import sys; sys.path.insert(0, '.')
from cloud.session_transfer import _r2_config, _r2_client_from, r2_bucket
c = _r2_client_from(_r2_config()); b = r2_bucket()
r = c.list_objects_v2(Bucket=b, Prefix='<partner>/<session>/render/')
[print(f\"  {o['Size']/1e6:>9.1f} MB  {o['Key']}\") for o in r.get('Contents', [])]"
```

R2 is the store of record (#404); GCS holds gcp-job data only and a session prefix there should
be empty.

**Resolving the target session.** `cloud.session_transfer` has no cross-partner lister — its one
listing helper is session-scoped, so it *confirms* a candidate rather than finds one:
`list_session_r2('<partner>', '<session>')` returns that session's keys (empty list = not in R2 —
wrong id, or never uploaded). Enumerate candidates from disk: partners are the directories under
`/Volumes/Studio/projects/`, sessions the `session_*` dirs inside one. Offer the list — the owner
still has to name the target before anything destructive runs (safety rule 1).

## Where things live

- `scripts/e2e_reset.sh` (this skill) — reset ritual, no fire.
- `scripts/monitor_e2e.py` (this skill) — one ~9.5-min watch window; run in background.
- `scripts/smoke_regen.sh` (this skill) — external-Terminal local EDL regen; writes `.regen_done`.
- `scripts/edl_truncate.py` (this skill) — first-N-minutes EDL + the pre-push row table.
- `scripts/monitor_render.py` (this skill) — one ~9.5-min window on a direct-submit render.
- `<repo>/scripts/cloud_render_submit.sh <partner>/<session> [--code-ref REF] [--max-cuts N]` —
  direct render submit; claims the session doc (zombie fence), prints the done-marker key.
- `<repo>/scripts/request_finish.sh <partner>/<session>` — production approval, leg 2.
- `<repo>/scratch/e2e_anraga_406.sh` — the owner's original single-session ritual, for background.
- `<repo>/scratch/transition_smoke/` — the PR #415 smoke this mode was distilled from: the
  original `regen_edl.command` and the truncated EDL. (It also holds downloaded footage and
  extracted frames from back when that was the ritual — historical, not a model to copy.)
- `<repo>/infra/workflows/{session_to_edl,finish_and_render}.yaml` — the two workflows, including
  the action-id parsing and the `cloud-stable` default.
