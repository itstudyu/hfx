#!/usr/bin/env bash
# verify-approval.sh — Hard gate for /hfx:run.
#
# Reads `approved_at` and `content_sha` from plan.md frontmatter, recomputes
# the current content_sha, and aborts if either is missing or if the sha has
# drifted (i.e., plan.md or plan.*.md was modified after approval).
#
# Usage: verify-approval.sh <ticket-dir>
# Exit codes:
#   0 — approved and sha matches; safe to dispatch.
#   1 — not approved (approved_at null/empty).
#   2 — usage error.
#   3 — sha mismatch (plan changed after approval; re-approve required).
#   4 — internal error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: verify-approval.sh <ticket-dir>" >&2
  exit 2
fi

ticket_dir="$1"
plan="$ticket_dir/plan.md"

if [ ! -f "$plan" ]; then
  echo "error: plan.md not found in $ticket_dir" >&2
  exit 2
fi

# Resolve sibling script path regardless of cwd.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract a frontmatter field value (value on same line as key).
read_field() {
  local key="$1"
  awk -v k="$key" '
    BEGIN { in_fm=0; count=0 }
    /^---[[:space:]]*$/ {
      count++
      if (count == 1) { in_fm=1; next }
      if (count == 2) { in_fm=0; exit }
    }
    in_fm && $0 ~ "^" k ":" {
      sub("^" k ":[[:space:]]*", "")
      gsub(/^["'"'"']|["'"'"']$/, "")  # strip surrounding quotes
      print
      exit
    }
  ' "$plan"
}

approved_at="$(read_field "approved_at" || true)"
stored_sha="$(read_field "content_sha" || true)"

# approved_at must be a non-empty, non-"null" value.
case "$approved_at" in
  ""|"null"|"~")
    echo "abort: plan.md is not approved (approved_at = '$approved_at')." >&2
    echo "hint:  run /hfx:plan and complete the [a]pprove gate first." >&2
    exit 1
    ;;
esac

# content_sha must be present.
case "$stored_sha" in
  ""|"null"|"~")
    echo "abort: plan.md has no content_sha; cannot verify integrity." >&2
    echo "hint:  re-run /hfx:plan and complete the [a]pprove gate." >&2
    exit 1
    ;;
esac

# Recompute and compare.
current_sha="$(bash "$script_dir/compute-sha.sh" "$ticket_dir")" || {
  echo "error: failed to compute current sha" >&2
  exit 4
}

if [ "$current_sha" != "$stored_sha" ]; then
  echo "abort: content_sha mismatch — plan files changed after approval." >&2
  echo "       stored : $stored_sha" >&2
  echo "       current: $current_sha" >&2
  echo "hint:  re-run /hfx:plan with [e]dit to re-approve the new state." >&2
  exit 3
fi

echo "ok: approved_at=$approved_at sha=$stored_sha"
exit 0
