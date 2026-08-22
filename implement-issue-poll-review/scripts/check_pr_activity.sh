#!/usr/bin/env bash
# Check a PR for NEW reviewer activity since a marker timestamp.
#
# Usage: check_pr_activity.sh <owner/repo> <pr_number> [since_iso8601]
#   since_iso8601: only surface activity at/after this time (default: epoch).
#
# Prints state/merge/review-decision, plus reviews, inline review comments, and
# non-bot conversation comments newer than <since>, and the labels.
# Exit 0 on success; the caller reads the output and decides.
#
# Notes:
#  - Pipes `gh` JSON through real `jq` (NOT `gh --jq`): gh's --jq is a single
#    filter string and does NOT accept jq's --arg, so the timestamp must be
#    injected via a piped `jq --arg`.
#  - Uses --json / `gh api` to dodge the Projects-classic GraphQL error that
#    breaks bare `gh pr view` / `gh issue view`.
#  - Bot filter is heuristic; adjust the regex for your org's bots/agents.
set -euo pipefail

REPO="${1:?owner/repo required}"
PR="${2:?pr number required}"
SINCE="${3:-1970-01-01T00:00:00Z}"

BOTS='github-actions|copilot|dependabot'

echo "=== state / merge / review decision ==="
gh pr view "$PR" --repo "$REPO" --json state,mergedAt,reviewDecision \
  | jq '{state, mergedAt, reviewDecision}'

echo "=== reviews submitted since $SINCE ==="
gh pr view "$PR" --repo "$REPO" --json reviews \
  | jq --arg since "$SINCE" \
    '[.reviews[] | select(.submittedAt >= $since)
      | {author: .author.login, state: .state, at: .submittedAt, body: (.body[0:600])}]'

echo "=== inline review comments since $SINCE ==="
gh api "repos/$REPO/pulls/$PR/comments" \
  | jq --arg since "$SINCE" \
    '[.[] | select(.created_at >= $since)
      | {author: .user.login, at: .created_at, path: .path, line: .line, body: (.body[0:600])}]'

echo "=== conversation comments since $SINCE (non-bot) ==="
gh api "repos/$REPO/issues/$PR/comments" \
  | jq --arg since "$SINCE" --arg bots "$BOTS" \
    '[.[] | select(.created_at >= $since)
      | select(.user.login | test($bots) | not)
      | {author: .user.login, at: .created_at, body: (.body[0:600])}]'

echo "=== labels (watch for agent-changes-requested) ==="
gh pr view "$PR" --repo "$REPO" --json labels | jq '[.labels[].name]'
