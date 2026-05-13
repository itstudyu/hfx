#!/usr/bin/env bash
# compute-sha.sh — Compute the content_sha for a ticket.
#
# The content_sha is the sha256 of the concatenated plan.md and plan.*.md
# files in the ticket directory, with the `content_sha:` and `approved_at:`
# lines stripped from plan.md so the hash only covers planning content,
# not the gate metadata itself.
#
# Usage: compute-sha.sh <ticket-dir>
# Prints: 64-char hex digest on stdout. Exit 0 on success.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: compute-sha.sh <ticket-dir>" >&2
  exit 2
fi

ticket_dir="$1"

if [ ! -d "$ticket_dir" ]; then
  echo "error: ticket directory does not exist: $ticket_dir" >&2
  exit 2
fi

plan="$ticket_dir/plan.md"
if [ ! -f "$plan" ]; then
  echo "error: plan.md not found in $ticket_dir" >&2
  exit 2
fi

# Pick sha256 binary (macOS: shasum -a 256, Linux: sha256sum).
if command -v sha256sum >/dev/null 2>&1; then
  sha_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha_cmd="shasum -a 256"
else
  echo "error: neither sha256sum nor shasum is available" >&2
  exit 3
fi

# Strip the gate metadata lines from plan.md so they don't self-reference.
# Then concat with all plan.*.md (worker plans) in sorted order.
{
  sed -E '/^(content_sha|approved_at):.*$/d' "$plan"
  # shellcheck disable=SC2012
  ls "$ticket_dir"/plan.*.md 2>/dev/null | sort | while IFS= read -r f; do
    [ -f "$f" ] && cat "$f"
  done
} | $sha_cmd | awk '{print $1}'
