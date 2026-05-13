#!/usr/bin/env bash
# move-ticket.sh — Move a ticket between active/, done/, and trash/.
#
# Safe: refuses to overwrite an existing destination, refuses to move outside
# .harness/tickets/, and never deletes — moves only.
#
# Usage: move-ticket.sh <harness-dir> <ticket-id> <done|trash>

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: move-ticket.sh <harness-dir> <ticket-id> <done|trash>" >&2
  exit 2
fi

harness_dir="$1"
ticket_id="$2"
target="$3"

case "$target" in
  done|trash) ;;
  *)
    echo "error: target must be 'done' or 'trash' (got: $target)" >&2
    exit 2
    ;;
esac

# Sanity: ticket_id must match a strict charset (letters, digits, dash,
# underscore). This rejects path separators, .., leading dots, lone `.`,
# and anything else that could escape the active/ subdirectory.
if ! printf '%s' "$ticket_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'; then
  echo "error: ticket_id must match [A-Za-z0-9_-] (got: '$ticket_id')" >&2
  exit 2
fi

src="$harness_dir/tickets/active/$ticket_id"
dst="$harness_dir/tickets/$target/$ticket_id"

if [ ! -d "$src" ]; then
  echo "error: source ticket not found: $src" >&2
  exit 2
fi

# Extra safety: refuse if `src` is a symlink (could point outside the harness).
if [ -L "$src" ]; then
  echo "error: source ticket is a symlink, refusing to move: $src" >&2
  exit 2
fi

if [ -e "$dst" ]; then
  echo "error: destination already exists: $dst" >&2
  echo "hint:  remove or rename it manually first." >&2
  exit 2
fi

mkdir -p "$(dirname "$dst")"
mv "$src" "$dst"

echo "ok: moved $ticket_id to $target/"
