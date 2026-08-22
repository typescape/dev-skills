#!/usr/bin/env bash
# PR discovery + update-watch for the plan-issue-poll-review skill.
# Run via Bash `run_in_background: true` (HARNESS-TRACKED) so the harness
# re-invokes you when it exits. Do NOT use nohup — that won't notify you.
#
#   pr_watch.sh find  <owner/repo> <issue#>        [window_sec=7200] [interval_sec=600]
#     Poll for an OPEN PR that references the issue (matched in title, body,
#     or branch name). Prints "PR_FOUND <pr#>\t<url>" and exits 0 on a hit;
#     "PR_DISCOVERY_TIMEOUT ..." if the window lapses (re-arm to keep waiting).
#
#   pr_watch.sh watch <owner/repo> <pr#> <prev_sha> [window_sec=7200] [interval_sec=600]
#     Poll a known PR for new commits. Prints "PR_UPDATED <sha>" when the head
#     moves (→ re-review the diff since <prev_sha>); "PR_<STATE>" if the PR is
#     no longer OPEN (closed/merged → stop); "NO_UPDATE_TIMEOUT ..." on lapse.
#
# Notes:
#  * Requires `gh` authenticated for <owner/repo>.
#  * Interval default 600s (10 min). Sleeps ≥300s miss the prompt cache; that's
#    fine for a long PR wait, but for sub-5-min polling prefer a short interval.
set -euo pipefail

mode=${1:-}
case "$mode" in
  find)
    repo=${2:?repo}; issue=${3:?issue#}; window=${4:-7200}; interval=${5:-600}
    end=$((SECONDS + window)); n=0
    while [ "$SECONDS" -lt "$end" ]; do
      n=$((n + 1))
      pr=$(gh pr list --repo "$repo" --state open \
             --json number,title,body,url,headRefName \
             --jq ".[] | select((((.title)+\" \"+(.body // \"\")+\" \"+(.headRefName))) | test(\"#?${issue}([^0-9]|\$)\")) | \"\(.number)\t\(.url)\"" \
             2>/dev/null | head -1 || true)
      if [ -n "$pr" ]; then echo "PR_FOUND $pr (after $n checks)"; exit 0; fi
      echo "check $n: no PR referencing #${issue} yet ($(date +%H:%M))"
      sleep "$interval"
    done
    echo "PR_DISCOVERY_TIMEOUT after ${window}s ($n checks)"
    ;;
  watch)
    repo=${2:?repo}; pr=${3:?pr#}; prev=${4:?prev_sha}; window=${5:-7200}; interval=${6:-600}
    end=$((SECONDS + window)); n=0
    while [ "$SECONDS" -lt "$end" ]; do
      n=$((n + 1))
      cur=$(gh api "repos/$repo/pulls/$pr" --jq .head.sha 2>/dev/null || true)
      state=$(gh pr view "$pr" --repo "$repo" --json state --jq .state 2>/dev/null || true)
      if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then echo "PR_UPDATED $cur (after $n checks)"; exit 0; fi
      if [ -n "$state" ] && [ "$state" != "OPEN" ]; then echo "PR_${state}"; exit 0; fi
      echo "check $n: no new commits on #${pr} ($(date +%H:%M))"
      sleep "$interval"
    done
    echo "NO_UPDATE_TIMEOUT after ${window}s ($n checks)"
    ;;
  *)
    echo "usage: pr_watch.sh find <owner/repo> <issue#> [window] [interval]"
    echo "       pr_watch.sh watch <owner/repo> <pr#> <prev_sha> [window] [interval]"
    exit 2
    ;;
esac
