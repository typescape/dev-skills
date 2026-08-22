"""One ~9.5-min watch window for a DIRECT-SUBMIT smoke render.

Usage: monitor_render.py <partner> <session> <marker_rel_key> <fresh_after_iso>

`marker_rel_key` is what `scripts/cloud_render_submit.sh` printed on the
`marker :` line — the basename is enough (`finish.direct-<short>.done.json`).
`fresh_after_iso` is the submit time; a naive stamp is read as UTC.

Exit: 0 = done marker present, 1 = a step reported failed since the submit,
3 = window elapsed (re-arm the SAME command). A smoke normally lands inside
1-2 windows.

Run it as a BACKGROUND task — one window is ~9.5 min of polling.
"""
import datetime as dt
import json
import subprocess
import sys
import time

REPO = "/Users/llwire/src/projects/infinit-studio"
sys.path.insert(0, f"{REPO}/orchestrator")

if len(sys.argv) < 5:
    raise SystemExit("usage: monitor_render.py <partner> <session> "
                     "<marker_rel_key> <fresh_after_iso>")
CREATOR, SESSION, MARKER = sys.argv[1], sys.argv[2], sys.argv[3]
FRESH_AFTER = dt.datetime.fromisoformat(sys.argv[4].replace("Z", "+00:00"))
if FRESH_AFTER.tzinfo is None:  # naive stamp == UTC, never local
    FRESH_AFTER = FRESH_AFTER.replace(tzinfo=dt.timezone.utc)
DEADLINE = time.time() + 9.5 * 60

from cloud.session_transfer import list_session_r2  # noqa: E402


def marker_exists():
    try:
        keys = list_session_r2(CREATOR, SESSION, prefix="_workflow/")
    except Exception:
        return False
    names = list(keys) if not isinstance(keys, dict) else list(keys)
    return any(str(k).endswith(MARKER) for k in names)


def fresh_steps():
    out = subprocess.run(
        [f"{REPO}/orchestrator/venv/bin/python", "-c", (
            "import json,sys;"
            f"sys.path.insert(0,'{REPO}/orchestrator');"
            "from cloud.status import read_session_doc;"
            f"d=read_session_doc('{CREATOR}','{SESSION}');"
            "print(json.dumps(d.get('steps',{}), default=str))")],
        capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        return {}
    steps = json.loads(out.stdout.strip() or "{}")
    # Step dicts MERGE on write, so stale `error`/`seconds` keys ride along on
    # a newer write. `at` is an EPOCH-MS STRING (ISO tolerated as fallback).
    # Only steps stamped at/after the submit belong to this render.
    fresh = {}
    for name, s in steps.items():
        at = s.get("at")
        if not at:
            continue
        try:
            ts = dt.datetime.fromtimestamp(float(at) / 1000.0, dt.timezone.utc)
        except (TypeError, ValueError):
            try:
                ts = dt.datetime.fromisoformat(str(at).replace("Z", "+00:00"))
            except ValueError:
                continue
            if ts.tzinfo is None:
                ts = ts.replace(tzinfo=dt.timezone.utc)
        if ts >= FRESH_AFTER:
            fresh[name] = {"status": s.get("status"),
                           "at": ts.isoformat(timespec="seconds")}
    return fresh


while time.time() < DEADLINE:
    if marker_exists():
        print("DONE-MARKER FOUND")
        sys.exit(0)
    fresh = fresh_steps()
    print(f"[{dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')}] "
          f"{json.dumps(fresh)}", flush=True)
    for name, s in fresh.items():
        if s.get("status") == "failed":
            print(f"STEP FAILED: {name}")
            sys.exit(1)
    time.sleep(45)
print("STILL-RUNNING (window elapsed)")
sys.exit(3)
