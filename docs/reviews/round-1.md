# Critical review — round 1

**Reviewer:** fresh `Plan` sub-agent, no prior context.
**Files reviewed:** all plugin files + smoke-tested scripts.
**Verdict:** 2 critical issues found.

---

## CRIT-1 — Worker dispatch ignores user-installed `.harness/agents/`

`/hfx:run` dispatches via `subagent_type="hfx:<worker>"`. The `hfx:`
namespace prefix resolves to the **plugin-shipped** `agents/workers/<name>.md`,
not to the user's `.harness/agents/workers/<name>.md` copy. So:

- `/hfx:init`'s per-worker model override is silently dropped.
- `/hfx:edit-worker`'s edits are silently dropped.
- README's promise of "editable workers" is non-functional.

**Resolution chosen:** option (a) — `/hfx:init` writes worker copies to
`.claude/agents/<name>.md` (project-level subagent location), and the
dispatcher uses `subagent_type="<name>"` (no plugin prefix). Plugin-shipped
`agents/workers/*.md` remain as templates/seeds, not as the runtime
agents.

## CRIT-2 — `/hfx:run` does not refuse a worker missing from `.harness/agents/workers/`

A stale or hand-edited `plan.md` could reference a worker the user
removed. The dispatcher would silently fall back to whatever agent
matched the name (compounded by CRIT-1).

**Resolution chosen:** add a Step 2b in `/hfx:run` that lists installed
workers and aborts if any step's worker is not installed.

---

## Fixes applied

1. **`skills/init/SKILL.md` Step 3 §5** — copy workers to `.claude/agents/`
   instead of `.harness/agents/workers/` (and helpers similarly).
2. **`skills/run/SKILL.md` Step 2b** — added explicit installed-workers
   check before dispatch.
3. **`skills/run/SKILL.md` Step 4 dispatch** — `subagent_type="<worker>"`
   (no `hfx:` prefix for runtime workers).
4. **`skills/edit-worker/SKILL.md`** — target path changed to
   `.claude/agents/<name>.md`; refuses to touch plugin-shipped agents.
5. **`skills/status/SKILL.md`** — installed-workers check via
   `.claude/agents/` listing.
6. **`tests/scenario.md`** — validation commands updated to inspect
   `.claude/agents/` instead of `.harness/agents/workers/`.
7. **`README.md`** — file-layout diagram updated.

## Out-of-bounds notes

The reviewer noted but explicitly did not classify as critical:
- `Agent` vs `Task` tool name ambiguity. The plugin uses `Agent` per the
  user's own brief. No change.
- `compute-sha.sh` exits 1 if no `plan.*.md` exist, but the plan SKILL
  always writes at least one. Unreachable in practice; no change.

Round 1 verdict: 2 critical → fixes applied → proceed to round 2.
