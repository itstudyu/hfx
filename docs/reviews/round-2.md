# Critical review — round 2

**Reviewer:** fresh `Plan` sub-agent, no prior context.
**Mandate:** verify round-1 fixes + look for new critical issues.
**Verdict:** 3 critical issues found.

---

## CRIT-1 — `code-analyst` dispatched with stale `hfx:` prefix

`/hfx:plan` and the seeded `templates/planner-policy.md` still told the
planner to dispatch the helper as `subagent_type="hfx:code-analyst"`.
After the round-1 fix (workers/helpers live at `.claude/agents/`), the
namespaced name resolves to nothing at runtime.

**Fix applied:** changed both call sites to `subagent_type="code-analyst"`
with a one-line note explaining why.

## CRIT-2 — `edit-worker` SKILL frontmatter `description:` still pointed at `.harness/agents/workers/`

The skill body was correct after round 1, but the frontmatter
`description:` still referenced the old path. Frontmatter is the field
Claude uses to match skills to user intent, so the stale string would
mislead invocation.

**Fix applied:** description updated to read `.claude/agents/*.md`.

## CRIT-3 — `move-ticket.sh` accepted `ticket_id="."` as valid (destructive)

The original guard rejected `*/*`, `*..*`, and `""`. A single `.` slips
through all three: with `ticket_id="."`, `mv` would move the entire
`active/` directory contents under `done/.`, effectively wiping all
active tickets in one shot. `.hidden` ids and a few similar inputs also
slipped through.

**Fix applied:**
1. Replaced glob-case rejection with a strict charset regex
   `^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$` — must start with alnum, only
   alnum/dash/underscore allowed, length ≤ 128.
2. Added a second check: refuse if `src` is a symlink (defense in
   depth — even if a valid-looking id pointed at a symlink, do not
   follow it).

**Verification:** smoke-tested 6 cases:
- valid id → moved (exit 0).
- `"."` → rejected (exit 2).
- `".hidden"` → rejected (exit 2).
- `"../evil"` → rejected (exit 2).
- `""` → rejected (exit 2).
- symlink target → rejected (exit 2).

All pass.

---

## What reviewer confirmed working

- Hard gate unbypassable: `/hfx:run` Step 2 always calls
  `verify-approval.sh`; script rejects null/empty `approved_at`, null
  `content_sha`, and any sha drift (round-1 already verified by my own
  smoke test).
- `compute-sha.sh` deterministic across approval and verify time
  (strips gate fields, sorts worker plans).
- SKILL `allowed-tools:` vs agent `tools:` correctly split.
- `disable-model-invocation: true` consistently on all 5 user-only skills.
- `isolation: worktree` only on writer workers.
- Scenario validation commands and test PASS criteria now align with
  the actual SKILL behavior (round-1 fix held).

## Out-of-bounds notes

- Reviewer flagged a non-critical concern about `compute-sha.sh` portability:
  macOS `ls` vs Linux `ls` could differ in collation. But the script
  pipes through explicit `sort`, so output is deterministic. No change.
- Reviewer ignored task-tracker reminders, correctly (its review is
  stateless).

Round 2 verdict: 3 critical → fixes applied → proceed to round 3.
