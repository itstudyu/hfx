# Changelog

All notable changes to hfx are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/).

## v0.0.5.13 — 2026-05-17

### Fixed
- Reviewer `maxTurns` raised 15→30 (spec, quality). Workers get 30
  turns; reviewers were dying mid-investigation without a verdict.
- `/hfx:run` Step 4a.2 now treats "no verdict from reviewer" as
  failed and forbids the main session from performing the review
  inline. Closes a real self-evaluation incident in
  2026-05-17-modern-login-page (planner verdicted its own plan as
  SPEC_PASS after the reviewer twice died at turn limit).
- `/hfx:run` Step 4 Agent call now explicitly passes
  `isolation="worktree"` when the worker frontmatter declares it.
  The frontmatter key alone was not being honored by Claude Code,
  so all worktree-based safeguards (Step 4.5 hand-off,
  `handoff-worktree.sh`) were dead code since v0.0.5.4. Confirmed
  on disk: `.claude/worktrees/` empty and `results.md` self-reported
  "isolation: worktree が有効化されず".
- Dispatch prompts now inline the required verdict line
  (`## Status` for workers, `## Spec review result` for
  spec-reviewer). The previous "follow your system prompt"
  reference was insufficient under long tool-use loops.

## v0.0.5.12 — 2026-05-16

### Fixed
- `/hfx:run` Step 4.5 had three `` ```! `` preprocess fences with
  runtime placeholders (`<worktree-dir>`, `<TMP_MANIFEST>`, sample
  manifest paths). Claude Code's `` ```! `` syntax runs the fenced
  command at preprocess time, BEFORE the model can substitute values
  — same class of bug as commit `2e16611` fixed for `<ticket-id>` in
  plan/run SKILLs. Symptom: `handoff-worktree.sh` was called with
  literal `<worktree-dir>` as its first argument and exited with
  `error: not a directory: <worktree-dir>`. Converted Steps 4.5.3,
  4.5.4, and 4.5.6 to plain `` ```bash `` instructional fences with
  explicit "use the Bash tool to substitute and run" wording.
- Step 4.5.4 also gained a hard precondition: skip the handoff if
  the worktree path is empty/missing, the manifest is empty, or the
  worker reported BLOCKED / NEEDS_CONTEXT (zero-change runs leave no
  worktree behind, because Claude Code auto-cleans them).
- `handoff-worktree.sh` now detects placeholder text (`<...>`) or
  empty args and exits 2 with a message pointing at the SKILL bug,
  as a defense-in-depth backstop.

### Why
Observed in hfx-test ticket `2026-05-16-login-screen-with-mock-auth`.
This is the second occurrence of the `` ```! ``-with-placeholders
pattern (first was `<ticket-id>` in `2e16611`). The fence runs in
preprocessing; the model never sees an opportunity to substitute.
Any `!`-fence whose body contains `<...>` placeholders is a bug.

## v0.0.5.11 — 2026-05-16

### Fixed
- `/hfx:init` Step 1 now uses **two** `AskUserQuestion` calls (4 + 1)
  instead of one bundled call. v0.0.5.9's added Language question
  pushed the total to 5, hitting `AskUserQuestion`'s hard 4-question
  cap and causing every init's first call to fail with `Invalid tool
  parameters` (the LLM recovered by self-splitting, but the SKILL was
  documenting an impossible call). Split is now explicit.

## v0.0.5.10 — 2026-05-16

### Added
- `/hfx:init` Step 2.5: for any worker the user names that is NOT a
  shipped template (`backend` / `frontend` / `docupdater`), the init
  flow now asks for an explicit Source — URL (WebFetched), file path
  (Read), or short prose — and refuses to write the worker from
  training-data recollection. Closes a real hallucination case:
  v0.0.5.9 silently invented ~50 "Angular 21" rules when the user
  named `https://angular.dev/style-guide` as the reference.

### Changed
- `planner-policy.md` §8 Language: clarified that the conversation
  channel mirrors the user's most recent message **even when the user
  is asking about an artifact**. Previously the rule was ambiguous
  enough that a Korean-language chat question about a Japanese-
  language artifact could trigger a Japanese reply.

## v0.0.5.9 — 2026-05-16

### Added
- `/hfx:init` asks for the project's artifact language (English,
  한국어, 日本語, or free-form). The value is written to
  `.harness/planner-policy.md` §8 and copied into every `plan.md`'s
  `## Constraints > Technical:` line so workers obey it. Conversation
  language continues to mirror the user.

## v0.0.5.8 — 2026-05-16

### Added
- Cross-worker contract requirement in `plan.md` `## Constraints >
  Technical:` when `worker_count >= 2` AND workers share a runtime
  path (HTTP request, queue message, file handoff, IPC, shared
  in-process state). Forces both workers to agree on wire shape
  before any code is written.
- `spec-reviewer` Hard rule #7 enforces the producer/consumer sides
  of the declared contract. Diverging payload keys or skipped
  validation is `SPEC_FAIL` regardless of per-task list status.

### Why
Workers run in isolated worktrees and cannot see each other's
decisions. Without an explicit contract, frontend could POST
`{username, pw}` while backend expects `{email, password}` — both
workers pass their own checks but integration breaks.

## v0.0.5.7 — 2026-05-16

### Added
- Worker rule (R9): no speculative configuration. Workers do not add
  function parameters, kwargs, flags, retry counts, timeout knobs,
  component props, slot APIs, or theme hooks that the plan does not
  require. Karpathy-style YAGNI for API surface.
- Planner rule (R4): push back on over-engineering. When the user
  proposes a materially more complex approach than a reasonable
  alternative, planner surfaces the simpler option as a Tier-2
  question (marked Recommended) instead of silently implementing
  the more complex path.

## v0.0.5.6 — 2026-05-16

### Added
- Worker rule (R10): no defensive over-engineering. Workers do not
  add `try/except`, null guards, retry loops, or fallback handlers
  for failure modes the plan does not list. "Just in case" makes
  real bugs invisible.
- Worker rule (R18): clean up only your own mess. Workers remove
  imports/variables their own diff orphaned, but never delete
  pre-existing dead code (scope creep — spec-reviewer will fail it,
  and it can silently break other files).

## v0.0.5.5 — 2026-05-16

### Changed
- Memory entries now use a 5-line self-describing skeleton:
  `Problem / Cause / Fix / Why / When-not-to-apply`. Every learning
  carries its own expiry condition so a future planner can decide
  if it still holds.
- Memory frontmatter adds a `files:` field anchoring each learning
  to the code location(s) it concerns, enabling future deterministic
  stale-detection.
- Write-side 3-gate: a learning is saved only if it (a) would have
  saved time on this very ticket, (b) is non-obvious from code, AND
  (c) is permanent — not a workaround for transient state.

## v0.0.5.4 — 2026-05-16

### Fixed
- Worker hand-off bug: workers with `isolation: worktree` left
  their output in `.claude/worktrees/agent-<id>/` and the main tree
  showed nothing. `/hfx:run` Step 4.5 now automatically copies
  changed files from the worktree to the main tree, using the
  worker's `## Files manifest` as an allow-list. Files outside the
  manifest are flagged `out_of_scope`; files conflicting with
  main-tree edits are flagged `conflicts` and the ticket is marked
  failed for manual reconciliation. Idempotent on re-run.

### Added
- `scripts/handoff-worktree.sh` (bash 3.2 compatible).

## v0.0.5.3 and earlier

Initial planner-led harness, hardened by seven rounds of
self-review (`docs/reviews/round-1..7.md`). See `git log` for
commit-level history.
