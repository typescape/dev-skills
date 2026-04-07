---
name: plan-review-changes
description: Find a PR labelled `agent-changes-requested`, read the review comments, interview the user about ambiguous feedback, then write a structured implementation plan back into the linked GitHub issue. Use when user wants to act on PR review feedback, mentions "address review comments", or wants to plan changes requested in a PR review.
---

# Plan Review Changes

Read code review feedback from a PR, resolve any ambiguities with the user, and write a concrete implementation plan into the linked GitHub issue.

## Process

### 1. Find and select the PR

Run:
```
gh pr list --label agent-changes-requested --state open --json number,title,author --jq '.[] | "#\(.number) \(.title) (\(.author.login))"'
```

Display the results and ask the user which PR to work on. If only one result, confirm it rather than auto-selecting.

### 2. Gather review comments

Fetch all review feedback for the selected PR:

```
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '[.[] | select(.body != "") | {author: .user.login, body: .body, state: .state}]'
gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '[.[] | {author: .user.login, body: .body, path: .path, line: .original_line}]'
```

Get the owner/repo from: `gh repo view --json nameWithOwner --jq '.nameWithOwner'`

Collect all non-empty comment bodies. Group inline comments by file path for context.

### 3. Find the linked issue

Parse the PR body for GitHub closing keywords (`Closes`, `Fixes`, `Resolves`, `close`, `fix`, `resolve` — case-insensitive) followed by `#N`.

```
gh pr view {number} --json body --jq '.body'
```

Extract the issue number, then fetch the issue:
```
gh issue view {issue-number} --json body,title
```

If no closing keyword is found in the PR body, stop and tell the user: "This PR's body doesn't contain a closing keyword (e.g. `Closes #N`). Please add one and try again."

### 4. Explore the codebase

Use the Agent tool with subagent_type=Explore to read the files and areas referenced in the review comments. Goal: understand the context well enough to classify each comment as either:

- **Clear-cut**: intent is unambiguous and there is one obvious implementation approach
- **Ambiguous**: unclear what the reviewer wants, or there are multiple valid approaches

### 5. Interview about ambiguous comments

For each ambiguous comment, ask the user one question at a time using the AskUserQuestion tool:

- Summarise the review comment
- Explain what makes it ambiguous
- Provide your recommended interpretation based on the codebase
- Ask which approach to take

Do not ask about clear-cut comments. Record all decisions.

### 6. Draft the plan

Produce two text blocks:

**Block A — `### Changes requested in review` content**

A bullet list where each item describes one required change in behavioral, durable language:
- Describe what the system should do differently — not which file to edit or which line to change
- Reference domain concepts, not implementation details
- One bullet per review comment or logical group of related comments
- If a decision was resolved in Step 5, reflect the chosen approach

**Block B — New acceptance criteria**

Checkbox items (matching the style already in the issue) for any new testable outcomes introduced by the review feedback. Skip criteria already covered by existing items in the issue.

### 7. Preview and confirm

Show the user:
1. Where Block A will be inserted (under `## What to build`, as a new subsection)
2. Where Block B items will be appended (under `## Acceptance criteria`)
3. The full text of each block

Ask the user to confirm before writing. If they request edits, revise and re-show.

Subsection heading rules:
- If **no** `### Changes requested in review` section exists yet → use heading `### Changes requested in review`
- If one **already exists** → use heading `### Changes requested in review — {YYYY-MM-DD}` (today's date)

### 8. Write to the issue

Edit the issue body:
- Insert Block A as a new `###` subsection at the end of the `## What to build` section (before the next `##` heading, or at end of body if none)
- Append Block B checkbox items at the end of the `## Acceptance criteria` section

Use `gh issue edit {issue-number} --body "$(cat <<'EOF'\n{full updated body}\nEOF\n)"` to write the changes.

Preserve all other sections exactly as-is.

### 9. Clean up

Remove the label from the PR:
```
gh pr edit {number} --remove-label agent-changes-requested
```

Confirm to the user: print the issue URL and a one-line summary of what was planned.
