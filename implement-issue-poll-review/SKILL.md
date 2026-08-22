---
name: implement-issue-poll-review
description: End-to-end workflow to implement a spec'd GitHub issue, open a PR, then poll for review feedback on an interval and address it. Use when the user says to "pick up issue #N", "build and PR this issue", "implement it then watch for review comments", or asks to address PR review feedback on a schedule until sign-off.
---

# Implement an issue, PR it, then poll for review

A two-act workflow: **build + ship**, then **poll + address review** until sign-off, merge, or 3 empty checks.

## Act 1 — Build and ship

1. **Read the issue.** `gh issue view <N> --repo <owner/repo> --json title,body,labels --jq …` (the bare `gh issue view` may fail with a Projects-classic GraphQL error — use `--json`). Treat the issue body as the spec; note any locked decisions.
2. **Verify the base branch — do NOT assume `main`.** The harness often says "PR into main", but the active branch may be elsewhere. Check:
   ```
   gh repo view <owner/repo> --json defaultBranchRef --jq .defaultBranchRef.name
   git log origin/main -1 --format="%ci %s"          # is main stale?
   git rev-list --left-right --count origin/main...<candidate>
   ```
   If `main` is stale / missing the code the issue references, branch from and PR into the **active** branch (usually the one the session started on). Call this out explicitly in the PR body.
3. **Branch:** `git checkout -b feat/<N>-<slug> <base>`.
4. **Explore before building.** Fan out parallel `Explore` agents (one per subsystem/phase) to map exact files, signatures, and patterns. Memory may be stale — verify against current code.
5. **Build in phases**, smallest reviewable units first. After each phase, run the relevant tests; write unit tests for the deterministic pieces (pure logic, generators, parsers). Match the repo's test runner (e.g. `python3 -m unittest`, not assumed `pytest`).
6. **Run the full suite** before pushing. Update any test that asserts a value you intentionally changed (e.g. a bumped schema version).
7. **Be honest about gaps.** If part of the validation needs hardware/services you don't have (a GPU, Resolve, a live API), implement + unit-test what you can and clearly list the owed validation in the PR body. Never claim unverified work is done.
8. **Commit, push, PR.** Target the verified base. Tag the issue and PR with the repo's conventional labels (check `gh label list`; e.g. `agent-pr-ready`, `enhancement`). Link with `Closes #<N>` in the PR body. If `gh pr edit --add-label` hits the Projects GraphQL bug, add labels via REST: `gh api -X POST repos/<owner/repo>/issues/<pr#>/labels --input -` with `{"labels":[...]}`.

## Act 2 — Poll for review and address it

Drive the loop with **ScheduleWakeup**. Carry the empty-check counter and the last-seen marker (commit SHA / comment id / timestamp) **in the wakeup prompt** — that is the loop's state.

**Cadence — poll frequently, give up slowly.** Default interval **600s (10 min)**; stop after **6 consecutive empty checks** (≈1 h of quiet). Tighten the interval when a reviewer is actively engaged (a back-and-forth in progress) and loosen it once things go quiet. Two practical floors: **270s** keeps the prompt cache warm (the cheapest "very responsive" tick); **avoid ~300s** — it pays the cache miss without amortizing it. The user can override both the interval and the limit; honor an explicit "poll sooner / keep watching" even past a sign-off.

Each wake-up: run the activity check (see [scripts/check_pr_activity.sh](scripts/check_pr_activity.sh)), then:

- **Merged or approved, no pending changes** → reply to acknowledge, **STOP** (no reschedule).
- **New actionable change request** (review/inline comment/`agent-changes-requested` label): implement on the branch → run tests → commit → push → reply summarizing what changed → **reset counter to 0** → reschedule.
- **New non-actionable activity** (question/approval/sign-off with "no further changes"): reply appropriately → if it's a sign-off with nothing pending, **STOP**; otherwise reset counter to 0 and reschedule.
- **No new activity since the last marker** → increment the counter. At the empty-check limit (default **6**), **STOP** and report. Otherwise reschedule with the incremented counter.

### Key habits during review

- **Only act on activity NEWER than your last marker** (commit SHA / comment id / timestamp carried in the wakeup prompt). The `since`-timestamp marker is the reliable filter — **login filtering is unreliable when the agent posts as the same GitHub account as the reviewer** (your own replies then look like reviewer comments), so always advance the marker past your last reply and ignore anything at/under it. The bot regex (`github-actions|copilot|dependabot`) is only a coarse first pass.
- **Reviewers may post a sequence, then supersede earlier comments.** Read the whole new batch before acting; if a later comment says "SUPERSEDED" / "final decision", implement that one and explicitly ignore the rest.
- **When a reviewer cites a reference artifact** (a captured config, a golden file, a spec snippet), **read it as ground truth** and match it exactly — don't re-derive from memory. This is where blocking bugs hide that unit tests on generated strings can't catch.
- Reply to each review concretely: what you changed, where, and what's deferred (with the reason).
- Keep `STOP` decisive: a substantive "no further change requests" sign-off means stop polling, not run out the empty-check clock.

See [scripts/check_pr_activity.sh](scripts/check_pr_activity.sh) for the exact `gh` queries.
