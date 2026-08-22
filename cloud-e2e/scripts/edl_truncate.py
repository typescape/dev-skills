"""Truncate an EDL to its first N minutes for a smoke render.

Usage: edl_truncate.py <edl_in> <edl_out> <minutes>

Keeps WHOLE rows that end inside the window, plus every `is_break_region` row
(break rows render nothing, so carrying them costs no GPU and keeps the seam
structure — and the row indices around it — intact). Drops the rest.

RECOMPUTES NOTHING: no re-timing, no renumbering, and the header counters
(`num_cuts`, `total_duration`, `statistics`) are deliberately left alone, so
the smoke EDL diffs cleanly against the full one and nothing downstream can
mistake it for a freshly derived plan. The renderer walks `cuts`.

Prints the kept rows with their structural flags. That table is the preflight:
confirm the feature-relevant seam is INSIDE the window before pushing and
paying for the render — an empty window renders a clean, useless video.
"""
import json
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: edl_truncate.py <edl_in> <edl_out> <minutes>")
src, dst, minutes = Path(sys.argv[1]), Path(sys.argv[2]), float(sys.argv[3])
WINDOW = minutes * 60.0

edl = json.loads(src.read_text())
cuts = edl.get("cuts")
if not isinstance(cuts, list) or not cuts:
    raise SystemExit(f"ABORT: no `cuts` array in {src}")

kept, dropped = [], 0
for i, c in enumerate(cuts):
    if float(c.get("end_time", 0.0)) <= WINDOW or c.get("is_break_region"):
        kept.append((i, c))
    else:
        dropped += 1
if not kept:
    raise SystemExit(f"ABORT: nothing ends within {minutes} min — window too small")

edl["cuts"] = [c for _, c in kept]
dst.write_text(json.dumps(edl, indent=2))

FLAGS = ("is_break_region", "single_camera_seam", "connection_modifier",
         "break_type", "reason")


def _brief(v):
    """One-line flag value — connection_modifier is a fat dict."""
    if isinstance(v, dict):
        return str(v.get("profile_name") or f"dict[{len(v)}]")
    s = str(v)
    return s if len(s) <= 32 else s[:29] + "..."


print(f"window   : {minutes} min ({WINDOW:.1f}s)   fps={edl.get('fps')}")
print(f"rows     : kept {len(kept)} / {len(cuts)}  (dropped {dropped})")
rendered = [c for _, c in kept if not c.get("is_break_region")]
if rendered:
    print(f"program  : ends {float(rendered[-1].get('end_time', 0.0)):.3f}s "
          f"across {len(rendered)} rendered rows")
print(f"wrote    : {dst}")
print("-- kept rows (row# start end cam flags) --")
for i, c in kept:
    flags = " ".join(f"{k}={_brief(c[k])}" for k in FLAGS
                     if c.get(k) not in (None, False, ""))
    ev = len(c.get("events") or [])
    print(f"  {i:>4} {float(c.get('start_time', 0)):>9.3f} "
          f"{float(c.get('end_time', 0)):>9.3f} cam{c.get('camera')} "
          f"events={ev} {flags}")
