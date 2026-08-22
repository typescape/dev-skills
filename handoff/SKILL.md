---
name: handoff
description: Synthesize a deep exploration, investigation, or design session into a self-contained handoff spec a fresh agent can pick up cold, plus a persisted memory pointer. Use when wrapping up an exploration and carrying work/context forward to another agent or a future session, when the user says "/handoff", "write a handoff", "hand this off", or "capture this before we lose context", or before context is about to be summarized away.
---

# Handoff

Turn everything learned in a long exploration into a durable, self-contained spec another agent can act on **with zero prior context** — then persist a memory pointer so it survives summarization.

The test of a good handoff: **a fresh agent who never saw the conversation can read the spec alone and continue the work correctly** — including avoiding the dead ends you already ruled out.

## Workflow

1. **Scope it.** Confirm what's being handed off (the conclusion + proposed direction) and pick a durable path: `plans/<topic>_spec.md` (create `plans/` if absent). Specs do NOT go in `scratch/` (throwaway) or get committed to someone else's PR branch.

2. **Draft the spec** from [TEMPLATE.md](TEMPLATE.md) — fill every section. Non-negotiables:
   - **Self-contained**: exact paths, data structures, function names, `file:line`, and commands — never "the script we used" or "that function."
   - **Preserve negative results**: a "do NOT repeat" section listing settled dead ends (what was tested and ruled out, with the numbers). This is often the most valuable part — it stops the next agent re-burning the cycles you spent.
   - **Numbers, not vibes**: cite the measurements, baselines, and metrics that grounded the conclusion.
   - **Keep vs reconsider**: for current code/branch state, say explicitly what's a validated building block vs what should be re-examined rather than extended.

3. **Persist a memory.** Write one project memory (per the memory rules) capturing the core finding in a few lines and pointing to the spec path; add a one-line pointer to `MEMORY.md`. This is what survives when the conversation is summarized.

4. **Surface loose ends** so the handoff is actually complete:
   - Artifacts that live **outside the repo** (Desktop, /Volumes, a temp dir) that the next agent needs — flag them and offer to copy them somewhere durable.
   - **Uncommitted/branch state** — what's on disk but not committed.
   - **Owed validation** — checks the conclusion still needs.

5. **Present & offer.** Give the spec path + a short summary of what it contains. If the handoff is to an implementing agent, offer to file it as a GitHub issue (matches the plan→issue→review pattern).

## Principles

- Write for a cold reader, not for yourself. Assume they distrust prior claims and will re-verify — give them the means to (paths, scripts, metrics).
- Capture the *map of the problem* (what drives X, what doesn't), not just the proposed answer.
- One level of links deep; keep the spec skimmable with tables and short sections.
- A handoff is for carrying context forward — it is NOT an implementation. Don't write code into the branch as part of it.

See [TEMPLATE.md](TEMPLATE.md) for the section-by-section skeleton.
