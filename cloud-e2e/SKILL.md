---
name: cloud-e2e
description: Run an infinit-studio cloud-pipeline validation — either the full two-phase E2E (reset to raw masters, fire session-to-edl, verify the EDL at preview_ready, fire the approval/render leg, report the render and its cost) or the cheap smoke render (local EDL regen on the branch under test, then a direct cloud render of just the first N minutes). Use when the user says "run the E2E", "reset and run an E2E", "two-phase E2E", "E2E the PR", "validate on the cloud pipeline", "smoke test", "smoke render", "test render of the first N minutes", "quick render check", or asks for a full pipeline validation run of a session.
---

# Cloud pipeline E2E

A real E2E burns real money (~$3.4/session all-in) and takes ~60-90 min across two legs.
The full ritual is two-phase: **EDL leg → owner-visible EDL check → render leg → deliverables.**
The smoke render is the cheap alternative when only the render needs eyes.

Repo is `/Users/llwire/src/projects/infinit-studio`. Reference session: `anraga/session_1776282026295`
— but partner and session are **parameters**. Never hardcode them into a new command.

## Which mode?

| | Full two-phase E2E | Smoke render |
|---|---|---|
| Proves | pipeline + workflow + cloud behavior end to end, from raw masters | how an EDL-side change **renders**, on real pixels |
| EDL comes from | the cloud EDL leg | a **local** regen on the branch under test |
| Renders | the whole program | the **first N minutes** |
| Cost / wall | ~$3.4 / ~60-90 min | ~$0.10-0.30 / ~10-15 min |
| Use it when | validating the pipeline itself, or producing an owner-approvable deliverable | checking a local EDL-side change cheaply before merging |

Full E2E = legs 1-2 below. Smoke = jump to [Smoke render](#smoke-render-cheap-mode).
A smoke exercises **none** of the cloud EDL code, so it never substitutes for an E2E when the
EDL leg is what changed.

## Safety rules (non-negotiable)

1. **Owner-go gate — and the go must name the session.** Never fire either leg unless the owner
   explicitly asked for this run in this conversation. Reset is destructive (wipes every derived
   artifact including past renders); the fire spends money. No inference, no "the plan implies it".
   If the request names no partner/session, do **not** guess and do **not** silently default to the
   reference session — it is the usual target, so propose it and wait: *"this will reset
   `anraga/session_1776282026295` — confirm?"*, and take only a confirmation that names the session.
   A destructive step (the reset, or the smoke's R2 `edl.json` overwrite) may run **only** against a
   session the owner named or confirmed in this conversation. Owner unsure what exists?
   REFERENCE.md → *Resolving the target session*.
2. **Failure budget = 2.** If a run fails: diagnose, fix, reset, re-run **once**. After a second
   failure, STOP and report. A third run needs a fresh owner go.
3. **code_ref must be a full 40-char sha.** The worker checkout REJECTS short shas.
   Get it with `git rev-parse "<ref>^{commit}"`. Pre-merge runs must pass the **same** code_ref
   to **both** legs — assembly only honors `${code_ref}` since commit cb00f66; before that it
   silently ran cloud-stable and produced stale-code EDLs that looked real.
   The production action-doc path always runs `cloud-stable`, so it validates merged+promoted
   code only. Testing a PR ⇒ use the `gcloud workflows execute` path on both legs.
4. **A smoke is cheap, not free — and not private.** It spends real money on the **production**
   render lane, and it **overwrites the session's `edl.json` in R2** (shared state, what the
   review player reads). Same explicit owner-go as a full run.
5. **Restore the EDL when a smoke ends.** After a smoke, R2 `edl.json` is the truncated copy.
   Before ANY subsequent full render, E2E, or owner review of that session, restore it — an
   owner-run push of the full regenerated EDL, or a fresh EDL leg. **A smoke that ends without
   restoring leaves a landmine for the next run**, and the next run looks fine while rendering
   3 minutes.
6. **R2 `edl.json` pushes are owner-run.** They are consistently permission-blocked for the
   agent. Write the exact command to a script, hand it over, wait for "pushed". Never work around
   the block.

## Leg 1 — EDL

```bash
scripts/e2e_reset.sh <partner> <session>     # masters-only R2 wipe + doc restamp; does NOT fire
```

Then fire exactly one of:

- **Production path** (validates cloud-stable, exercises the real trigger): create a
  `pipeline_actions` doc with ID `<partner>__<session>__<epoch-ms>`. The Eventarc trigger is
  **CREATED-only** — never update an existing doc, and the ms suffix is what makes every emit a create.
- **Pre-merge path** (testing a PR):
  ```bash
  gcloud workflows execute session-to-edl --location us-central1 --project infinit-partner \
    --data '{"partner_id":"<p>","session_id":"<s>","code_ref":"<full-40-char-sha>","bucket":"infinit-studio"}'
  ```

Record **T0 = epoch ms at fire time**. Everything downstream filters on it.

## Monitor

```bash
# the orchestrator venv, not system python — the monitor imports cloud.session_transfer
/Users/llwire/src/projects/infinit-studio/orchestrator/venv/bin/python \
  ~/.claude/skills/cloud-e2e/scripts/monitor_e2e.py <partner> <session> <t0_ms> edl
```

Run it as a **background** Bash task. Exit codes: `0` = preview_ready (**terminal for leg 1** —
the approval trigger means the render does NOT auto-fire), `1` = a step failed (diagnose before
doing anything else), `3` = window elapsed — just re-arm the identical command. A leg normally
takes 4-6 windows. preview_ready typically lands T+27-45 min.

## Verify the EDL before spending the render

At preview_ready, pull `edl.json` from R2 and check whatever this run was meant to prove
(transition_profile version, expected feature markers, cut count sanity). Firing the render on an
unverified EDL wastes the whole render spend.

```bash
cd /Users/llwire/src/projects/infinit-studio/orchestrator && venv/bin/python -c "
import sys; sys.path.insert(0, '.')
from cloud.session_transfer import read_file_r2, list_session_r2
import json; edl = json.loads(read_file_r2('<p>', '<s>', 'edl.json'))
print(edl.get('transition_profile'), len(edl.get('cuts', [])))"
```

## Leg 2 — render

- **Production path:** `scripts/request_finish.sh <partner>/<session>` (one slash-joined arg —
  creates the `__finish__` action doc, the same signal the review app's approval emits).
- **Pre-merge path:**
  ```bash
  gcloud workflows execute finish-and-render --location us-central1 --project infinit-partner \
    --data '{"partner_id":"<p>","session_id":"<s>","code_ref":"<same full sha as leg 1>"}'
  ```

Record a **new T0**, then monitor in `finish` mode — exit 0 on a fresh
`_workflow/finish.<executionId>.done.json` marker. Render leg is ~35-40 min fire-to-done.

## Deliverables (never skip)

**Do NOT download the render mp4, and do not cut stills, filmstrips or clips from it.** It is
multi-GB, the owner reviews it in the Infinit UI, and pulling it locally buys nothing. Report
where it is and leave it there.

1. Report the R2 key of `render/<name>.mp4` and its size so the owner can find it — a listing
   gives both without transferring bytes (snippet in REFERENCE.md → *R2 access*).
2. Pull only `.timing.json` (small — `read_file_r2` handles it) and report per-leg wall times and
   cost (GPU seconds × the class rate from `_DEFAULT_RATES` in
   `orchestrator/cloud/runpod_worker.py` — the single source of truth).
3. Verify the render against the EDL **from the numbers, not from pixels**: total frames in
   `.timing.json` ÷ fps must equal the program length the EDL predicts, and the per-cut
   `transition_frames` must equal the EDL's edge records × their frame counts. Predict both
   BEFORE the render and state them; a mismatch is the finding. **Read the real fps from the
   EDL** — never assume 25.

## Smoke render (cheap mode)

Local EDL regen on the branch under test, then a **direct** cloud render (no workflow, no
approval leg) of only the first N minutes. Steps 1-3 are local and free; the money starts at 5.

### 1. Copy the session into scratch

Never regen against the real session dir on `/Volumes/Studio`. Work in
`scratch/<purpose>_smoke/<partner>/<session>` inside the repo — a fresh copy, or a `pull_tree_r2`
of the session's artifacts.

- Pipeline wants camera masters locally ⇒ **symlink**, don't copy:
  `ln -s "/Volumes/Studio/projects/<p>/<s>/cameras" "<session_dir>/cameras"`.
- Staleness preflight refuses on an older copy ⇒ `--artifact-checks warn` (step 2). Fine here:
  a smoke validates the mechanism, not a bit-exact plan.

### 2. Regen the EDL locally

```bash
~/.claude/skills/cloud-e2e/scripts/smoke_regen.sh <session_dir> \
  [--steps "edl_generation edl_smoothing"] [--repo <checkout>] [--artifact-checks warn]
```

Writes a `.command` wrapper and opens it in **Terminal** — pipeline runs always go to an external
Terminal so the owner can follow live, never to the Bash tool; `arch -arm64` because Terminal runs
x86_64 against the universal2 venv. It runs
`run_pipeline.py <session_dir> --steps edl_smoothing --force-regen --no-firebase` (default steps;
add `edl_generation` before it when generation-side code changed — `--no-firebase` keeps the
production session doc untouched), tees to `regen_edl.log`, and writes the rc to
`<session_dir>/.regen_done`. Poll for that marker from here.

**Then read the log.** The smoothing/generation decision lines are usually the actual evidence a
smoke is after — the render only confirms they survive to pixels.

### 3. Truncate to the first N minutes

```bash
<repo>/orchestrator/venv/bin/python ~/.claude/skills/cloud-e2e/scripts/edl_truncate.py \
  <session_dir>/edl.json <session_dir>/edl.smoke.json <N>
```

Keeps whole rows ending inside the window plus every `is_break_region` row (break rows render
nothing — free to carry, and they keep the seam structure intact). Recomputes nothing.

**Pick N so the window contains at least one feature-relevant seam, and confirm it in the printed
row table BEFORE pushing.** Discovering an empty window after paying for the render is the
expensive way to learn this.

### 4. Push the truncated EDL — OWNER RUNS THIS

Write it to a script, hand the path over, wait for "pushed" (safety rule 6). `push_file_r2` is the
right tool — it stamps Content-Type, which #404 requires of every R2 writer.

```bash
cd <repo>/orchestrator && venv/bin/python -c "
import sys; sys.path.insert(0, '.')
from pathlib import Path
from cloud.session_transfer import push_file_r2
print(push_file_r2('<p>', '<s>', 'edl.json', Path('<session_dir>/edl.smoke.json')))"
```

Keep the full regenerated `edl.json` beside it — step 8 pushes it back.

### 5. Submit the render

```bash
cd <repo> && scripts/cloud_render_submit.sh <partner>/<session> --code-ref <branch-or-sha>
```

One RunPod job straight at the render endpoint, bypassing `finish-and-render`. Same full-sha rule
as the E2E: the script expands anything sha-ish via `git rev-parse "<ref>^{commit}"`, but a
**branch name passes through** and resolves on the worker — pass a sha when you need certainty
about which commit rendered. Record the submit time
(`date -u +%Y-%m-%dT%H:%M:%S+00:00`) and the `marker :` line it prints; the monitor needs both.

### 6. Monitor

```bash
<repo>/orchestrator/venv/bin/python ~/.claude/skills/cloud-e2e/scripts/monitor_render.py \
  <partner> <session> finish.direct-<short>.done.json <submit_iso>
```

Background Bash task. `0` = done marker, `1` = a step failed (diagnose before resubmitting),
`3` = re-arm the identical command. A smoke normally lands inside 1-2 windows.

### 7. Deliverables (never skip)

Same rule as the E2E: **do NOT download the mp4 and do not cut stills, filmstrips or clips.**
Report the R2 key of `render/<name>.smoke.mp4` and its size, pull only `.timing.json`, and report
GPU seconds × the class rate from `_DEFAULT_RATES`.

Verify from the numbers instead. A smoke's sharpest check is the frame count: predict the
truncated program's length from the EDL BEFORE submitting (kept rows + every transition's
borrowed frames), then confirm `.timing.json`'s total frames ÷ fps matches. The delta between
"with transitions" and "without" is usually a handful of frames, so it is an exact pass/fail on
whether the records reached the engine — sharper than eyeballing a blur. Per-cut
`transition_frames` should likewise equal the EDL's edge records × their frame counts. **Read
the real fps from the EDL** — never assume 25.

### 8. RESTORE the EDL — mandatory

The session's R2 `edl.json` is still the truncated smoke copy. Hand the owner the same push
command with the **full** regenerated `edl.json`, confirm it landed, and say so in the report.
Safety rule 5 — a smoke is not finished until this is done.

## Details

Gotchas that each cost a debugging session, cost/time bands, and R2 access patterns:
see [REFERENCE.md](REFERENCE.md). Read it before diagnosing any failure.
