---
name: plan-issue-poll-review
description: Lead/reviewer workflow — grill a feature design, plan it into a GitHub issue spec, hand off to an implementing agent, then poll for the resulting PR and review it against the plan until clean. Use when the user wants to plan/spec a feature into an issue and then review the PR, design something then have an agent build it and review their work, kick off an implementer and review on a schedule, or "plan this then review what comes back". Counterpart to implement-issue-poll-review (which builds the issue this writes and opens the PR this reviews).
---

# Plan an issue, hand off, then poll for the PR and review

Three acts: **plan into an issue**, **hand off** to an implementer, then **poll + review** the PR until it's clean. Counterpart to `implement-issue-poll-review` — keep the issue body compatible with what that skill consumes.

## Act 1 — Plan the feature into a GitHub issue

1. **Grill the design first.** Walk the decision tree one branch at a time, resolving each before the next, with a recommendation per branch (use the `grill-me` skill). Don't write the plan until the branches are settled.
2. **Explore the codebase to settle facts** instead of asking — read the actual code; memory may be stale.
3. **Spike the unverified.** For any load-bearing assumption ("does this tool/API actually work headless?", "is X reliable / fast enough?"), run a small de-risking experiment NOW and **judge by output, not docs/claims**. A wrong assumption baked into the plan costs the implementer dearly — a spike that fails here is the cheapest place to find out.
4. **Write the plan into the issue BODY** as the canonical spec (`gh issue create`/`gh issue edit --body-file`). The body is the single source of truth the implementer reads — **edit it as decisions change; don't scatter them across comments.** Include:
   - Context (why) + the **load-bearing decisions** (with rejected alternatives, briefly).
   - A **phased** plan, smallest reviewable units first, naming the **exact files** each phase touches and the patterns/utilities to reuse.
   - Any **schema/version bump** needed to retrigger regeneration on existing data.
   - **Validation gates** — including steps that **can't run in CI** (GPU, Resolve, live API) and are explicitly *owed*.
   - A collapsed appendix of spike findings + any captured **reference artifacts** (GUI-saved configs, golden snippets) — these become ground truth at review time.
5. **Record key decisions to memory** as you go so they survive into the review and any handoff.

(`gh issue view`/`edit` with bare output can hit a Projects-classic GraphQL error — use `--json`/`--body-file`.)

## Act 2 — Hand off

The issue is now a complete spec; an implementing agent picks it up (`implement-issue-poll-review`). Confirm the implementer's base-branch assumption is right if `main` is stale (the issue should say which branch its code lives on). Then start the review loop.

## Act 3 — Poll for the PR, then review until clean

**Discover the PR.** Launch a **harness-tracked** poller — `Bash` with `run_in_background: true` running an until-loop that exits on a hit (NOT `nohup`: a tracked task notifies you on exit, nohup doesn't). See [scripts/pr_watch.sh](scripts/pr_watch.sh) `find`. Default ~10 min interval, bounded window (~2h); re-arm if it lapses. (Keep poll `sleep`s short enough to respect the prompt-cache window, or use `ScheduleWakeup` for long waits.)

**Review against the plan's load-bearing decisions:**
- **Verify by reading the actual code** (and running/rendering where it matters). Never trust the commit message — or the author's reply that "it's addressed."
- When the plan captured a **reference artifact**, check the code against it **exactly**. That's where blocking bugs hide that string-only unit tests can't catch (e.g. a generated config whose syntax differs from the GUI-confirmed save).
- **Flag CI-impossible validation as owed** — don't block the PR on it.
- Post comments with **file:line + the fix** (`gh pr review --comment --body-file`, or `gh api repos/<repo>/pulls/<n>/comments` for inline). Lead with what's faithful, then the findings ranked by severity.

**Loop.** If you posted ≥1 change request: record the PR head SHA, launch a tracked watch for new commits ([scripts/pr_watch.sh](scripts/pr_watch.sh) `watch`). On a push, re-review the diff **since the last SHA** — confirm each finding is addressed **and** nothing regressed (read the patch + thread the new params, don't trust the changelog). Repeat until a re-review turns up nothing, then post a brief closing note. **If the first review found nothing, you're done.**
