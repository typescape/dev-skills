# Handoff spec template

Copy this skeleton into `plans/<topic>_spec.md` and fill every section. Drop sections only if genuinely N/A. Lead with the conclusion; a reader should grasp the point in the first 10 lines. Use tables liberally.

```md
# Spec: <topic / proposed direction>

**Status:** design / handoff. <one line: investigation complete; this is the direction.>
**Context branch:** `<branch>` (note if experimental/uncommitted — see §<branch state>).
**Reference target:** `<session / dataset / module under study>`.

---

## 1. The problem, and the core finding
<2–5 sentences: what we set out to do and the headline conclusion.>
- <key result, with the number that proves it>
- <key result …>

**What drives <the thing> (every candidate tested):** a table —
| candidate | drives? | detect with | status (confirmed / ruled out + evidence) |

## 2. The proposed model / direction
<the design the findings point to — concrete enough to start building, step-listed.>

## 3. Ground truth & how to measure
<the reference/baseline used to judge correctness, where it lives, and the exact metrics + baseline numbers to beat. How to re-run the comparison.>

## 4. Signals / inputs — what to use, what to avoid
- **USE:** <signal — how to compute, where it is / isn't available, why it's reliable.>
- **AVOID:** <signal — why it misleads, in what conditions.>
- **Ruled out (don't re-chase):** <list, with evidence pointers.>

## 5. Data inventory
A table of **every artifact**: path + structure/shape + units/coordinate system.
| artifact | path | what / structure |
Note any coordinate/time-base/identity conventions (e.g. which index = which thing).

## 6. Gotchas / conversions
<time-base conversions, coordinate transforms, indexing, caching — the exact functions/helpers, and the traps (e.g. "X is unreliable here; use Y instead"). This is where silent wrong-answers hide.>

## 7. Tools & scripts
| script / command | purpose |
<every script built or used (with its path), and key commands (build, run, test) with any warnings (e.g. "overwrites real artifacts — back up first").>

## 8. Codebase map
The relevant files → functions → the **seams to change**. Cite `file:line` where useful. Group by module.

## 9. Current code / branch state — keep vs reconsider
**Keep** (validated building blocks): <…>. **Reconsider / don't blindly extend:** <…>. What's committed vs on-disk.

## 10. Build & validation plan
Ordered steps; each with how it's validated against §3.

## 11. Open decisions
<the forks the next agent (or user) must decide, with the trade-offs.>

## 12. Do NOT repeat (settled)
<dead ends already explored, with the evidence that settled them — so they aren't re-burned.>
```

## Filling notes
- **§1 and §12 carry the most leverage.** The finding and the ruled-out list are what a cold agent can't reconstruct and most needs.
- Prefer exact over generic: `services.intervals.render_to_source`, not "the time helper"; `camera_N/facial_analysis.json` with its keys, not "the facial data."
- If a metric/baseline grounded a decision, put the number in — "74.1% baseline; all configs scored below it" beats "it didn't work well."
- Keep it skimmable: short sections, tables, one-level links. A 1-page-equivalent that's complete beats a sprawling doc.
