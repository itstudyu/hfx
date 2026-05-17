#!/usr/bin/env bash
# handoff-worktree.sh — Copy a worker's output from its isolated worktree
# back to the main project root.
#
# Why this exists
# ----------------
# Workers configured with `isolation: worktree` in their agent frontmatter
# run inside `.claude/worktrees/agent-<id>/`. When such a worker uses
# Edit/Write to create or modify files, those edits live in the worktree.
# They are typically left as untracked or uncommitted changes there — the
# Agent tool does not auto-merge them back into the main project tree.
#
# Result without this script: worker reports DONE, but `git status` in
# the main project shows nothing and the user has no files to look at.
# This was observed in ticket 2026-05-16-login-mock-screen (hfx-test).
#
# What this script does
# ---------------------
# Given a worktree dir + main project root + an allow-list of paths
# (the worker's `Files manifest` from plan.<worker>.md), it:
#
#   1. Enumerates untracked + modified files inside the worktree
#      (relative to the worktree's HEAD).
#   2. Filters to paths that match the allow-list (prefix match against
#      the relative path). Anything outside the allow-list is reported
#      as `out_of_scope` and NOT copied.
#   3. For each allowed file, compares against the same path in the
#      main project root:
#        - missing in main → copy.
#        - identical bytes → skip (idempotent re-run).
#        - different bytes → conflict; do NOT overwrite, report.
#   4. Emits a JSON report on stdout so the caller (/hfx:run) can
#      surface counts and conflicts to the user.
#
# What this script does NOT do
# ----------------------------
# - It does NOT merge git branches, cherry-pick commits, or touch the
#   worktree's git state. Only file content is copied.
# - It does NOT delete the worktree afterwards — that is Claude Code's
#   responsibility (and is needed if the user wants to inspect later).
# - It does NOT validate that the worker actually finished — the caller
#   only runs this when the worker reported DONE / DONE_WITH_CONCERNS.
#
# Usage
# -----
#   handoff-worktree.sh <worktree-dir> <project-root> <manifest-file>
#
# <manifest-file> is a newline-separated list of repo-relative paths
# (from `## Files manifest` — both `Create:` and `Modify:` entries).
# The caller is responsible for extracting these from plan.<worker>.md
# and writing them to a temp file before calling.
#
# Output: a JSON object on stdout, e.g.
#   {
#     "copied":       ["index.html", "style.css"],
#     "skipped_same": [],
#     "conflicts":    [],
#     "out_of_scope": []
#   }
#
# Exit codes
#   0 — success (whether or not conflicts/out_of_scope occurred; caller
#       reads JSON to decide). Conflict / out_of_scope are reported,
#       not fatal — only the caller knows whether to fail-fast.
#   2 — usage error or missing inputs.
#   3 — IO failure during copy.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: handoff-worktree.sh <worktree-dir> <project-root> <manifest-file>" >&2
  exit 2
fi

worktree_dir="$1"
project_root="$2"
manifest_file="$3"

# Placeholder / empty guard. The root cause this guards against is
# /hfx:run Step 4.5.4 being placed in a Claude Code ```! preprocess
# fence: the shell runs the literal command "<worktree-dir>" before
# the model can substitute the runtime value. Step 4.5.4 has been
# moved to a plain ```bash fence (substituted at execution time), but
# we still trip the alarm here for defense in depth.
case "$worktree_dir" in
  ""|*"<"*">"*)
    echo "error: handoff-worktree.sh received placeholder/empty worktree_dir ('$worktree_dir')." >&2
    echo "       caller did not substitute the value before invocation." >&2
    echo "       see skills/run/SKILL.md Step 4.5.4 — must use Bash tool, not a !-fence." >&2
    exit 2 ;;
esac
case "$manifest_file" in
  ""|*"<"*">"*)
    echo "error: handoff-worktree.sh received placeholder/empty manifest_file ('$manifest_file')." >&2
    echo "       caller did not substitute the value before invocation." >&2
    exit 2 ;;
esac

for d in "$worktree_dir" "$project_root"; do
  if [ ! -d "$d" ]; then
    echo "error: not a directory: $d" >&2
    exit 2
  fi
done

if [ ! -f "$manifest_file" ]; then
  echo "error: manifest file not found: $manifest_file" >&2
  exit 2
fi

# Resolve to absolute, no trailing slash (so prefix math is simple).
worktree_dir="$(cd "$worktree_dir" && pwd)"
project_root="$(cd "$project_root" && pwd)"

# Load the allow-list. Strip blank lines and leading "./" if present.
# Each entry is a repo-relative path, e.g. "index.html" or "src/app/page.tsx".
allow_list=()
while IFS= read -r line; do
  # strip CR (if file came from Windows), then trim, then drop blanks/comments
  line="${line%$'\r'}"
  line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue;; esac
  line="${line#./}"
  allow_list+=("$line")
done < "$manifest_file"

# is_allowed <relpath>  → exit 0 if allowed, exit 1 otherwise.
# A relpath is allowed if it equals an allow-list entry, OR if any
# allow-list entry is a directory prefix of it (so manifest "src/foo/"
# permits "src/foo/bar.ts").
is_allowed() {
  local rel="$1"
  local entry
  for entry in "${allow_list[@]+"${allow_list[@]}"}"; do
    if [ "$rel" = "$entry" ]; then return 0; fi
    case "$entry" in
      */) [ "${rel#"$entry"}" != "$rel" ] && return 0 ;;
      *)  [ "${rel#"$entry/"}" != "$rel" ] && return 0 ;;
    esac
  done
  return 1
}

# Collect candidate paths. Porcelain enumerates untracked directories
# as a single entry (`?? src/`), hiding per-file paths from the
# allow-list. `ls-files --others --exclude-standard` enumerates
# untracked files per-file (respecting .gitignore); `diff --name-only
# --diff-filter=ACMR HEAD` catches added/modified/staged/renamed
# files. For renames, diff emits the destination only — no arrow
# parsing needed (cleaner than the old porcelain switch).
candidates=()
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  candidates+=("$rel")
done < <(
  {
    git -C "$worktree_dir" ls-files --others --exclude-standard
    git -C "$worktree_dir" diff --name-only --diff-filter=ACMR HEAD
  } 2>/dev/null | sort -u
)

# Track deletions separately so the JSON report names them explicitly.
# Old script silently filtered deletions via `[ ! -f "$src" ]` at the
# copy step; that preserved behavior (no delete-propagation) but lost
# the signal. Workers may legitimately delete files (cleanup); the
# caller needs to know so it can decide policy.
deletions=()
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  deletions+=("$rel")
done < <(git -C "$worktree_dir" diff --name-only --diff-filter=D HEAD 2>/dev/null)

copied=()
skipped_same=()
conflicts=()
out_of_scope=()

for rel in "${candidates[@]+"${candidates[@]}"}"; do
  src="$worktree_dir/$rel"
  # only files; symlinks and submodules need policy we don't have yet.
  if [ ! -f "$src" ]; then continue; fi

  if ! is_allowed "$rel"; then
    out_of_scope+=("$rel")
    continue
  fi

  dst="$project_root/$rel"

  if [ ! -e "$dst" ]; then
    mkdir -p "$(dirname "$dst")" || { echo "error: mkdir failed for $(dirname "$dst")" >&2; exit 3; }
    cp "$src" "$dst" || { echo "error: cp failed for $rel" >&2; exit 3; }
    copied+=("$rel")
    continue
  fi

  # Existing destination — compare byte-for-byte.
  if cmp -s "$src" "$dst"; then
    skipped_same+=("$rel")
  else
    conflicts+=("$rel")
  fi
done

# Emit JSON. We build it by hand to avoid a jq dependency. bash 3.2 (the
# default on macOS) lacks `local -n` namerefs, so we pass entries as
# positional args instead of by name.
json_array() {
  # Usage: json_array "${arr[@]}". Emits a JSON array of strings.
  local first=1 v esc
  printf '['
  for v in "$@"; do
    if [ $first -eq 1 ]; then first=0; else printf ','; fi
    esc="${v//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '"%s"' "$esc"
  done
  printf ']'
}

printf '{'
printf '"copied":';       json_array "${copied[@]+"${copied[@]}"}"
printf ',"skipped_same":'; json_array "${skipped_same[@]+"${skipped_same[@]}"}"
printf ',"conflicts":';   json_array "${conflicts[@]+"${conflicts[@]}"}"
printf ',"out_of_scope":'; json_array "${out_of_scope[@]+"${out_of_scope[@]}"}"
printf ',"deletions":';   json_array "${deletions[@]+"${deletions[@]}"}"
printf '}\n'
