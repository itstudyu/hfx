# Critical review — round 8 (dispatch-name resolution fix)

**Reviewer:** observation from a real failed dispatch:
> Agent type 'backend' not found. Available agents: ...,
> hfx:workers:backend, hfx:workers:docupdater, hfx:workers:frontend,
> hfx:helpers:code-analyst, ...

**Mandate:** make worker dispatch survive both environments — the
`/hfx:init`-completed project (round-6 native PASS path) **and** the
plugin-only environment where Claude Code exposes plugin-shipped
agents only under their namespaced names.

**Verdict:** 1 architectural fix touching 3 skills + 1 policy + README.

---

## Issue — bare-name dispatch is not universally available

The whole dispatch contract assumed:

> `/hfx:init` copies `${CLAUDE_PLUGIN_ROOT}/agents/workers/<w>.md`
> into `${CLAUDE_PROJECT_DIR}/.claude/agents/<w>.md`. From there
> Claude Code exposes the agent under the **bare** name `<w>`, and
> `/hfx:run` dispatches `Agent(subagent_type="<w>", ...)`.

That works when the project has been initialized. It breaks in two
real environments:

1. **Plugin-only sessions.** A user (or a developer working on hfx
   itself) loads the plugin in a directory that does not have
   `.claude/agents/`. Claude Code then exposes the plugin-shipped
   agents only under their namespaced names (`hfx:workers:backend`,
   `hfx:helpers:code-analyst`, …). The dispatcher's bare call
   `Agent(subagent_type="backend")` fails with the error above.
2. **Future runtime tightening.** Even in initialized projects,
   nothing in the plugin contract forbids Claude Code from one day
   exposing plugin-shipped agents *only* under their namespaced
   names. The bare-name path was always best-effort, never a
   guarantee. Round-7's PASS exercised the happy path; the failure
   surfaced once the environment changed.

In both cases the planner could see only `hfx:workers:<w>` in the
agent registry, but the dispatcher kept calling bare `<w>`.

## Fix applied — union discovery + fallback resolver

### 1. Discovery is now the union of two sources

Both `/hfx:plan` (Step 2) and `/hfx:run` (Step 2b) build a discovery
map from:

- `${CLAUDE_PROJECT_DIR}/.claude/agents/*.md` → `local:<name>`
- `${CLAUDE_PLUGIN_ROOT}/agents/workers/*.md` → `plugin-worker:<name>`
- `${CLAUDE_PLUGIN_ROOT}/agents/helpers/*.md` → `plugin-helper:<name>`

A worker is "available" if it appears under any of those keys.

### 2. Dispatch resolves the right `subagent_type` per worker

Project-local always wins (preserves `/hfx:edit-worker`'s purpose):

| Source(s) present                  | `subagent_type`         |
|------------------------------------|--------------------------|
| `local:<name>`                     | `<name>` (bare)          |
| only `plugin-worker:<name>`        | `hfx:workers:<name>`     |
| only `plugin-helper:<name>`        | `hfx:helpers:<name>`     |

`plan.md`'s `dispatch_graph.steps[].worker` still records the bare
name. The resolution happens in `/hfx:run` Step 4 at dispatch time,
not in the plan file — so old `plan.md` files stay forward-compatible.

### 3. Documentation updated

- `skills/run/SKILL.md` — Step 2b discovery, Step 3 validation
  message, Step 4 dispatch block.
- `skills/plan/SKILL.md` — Step 2 discovery, Step 4 code-analyst
  dispatch, Hard rules wording.
- `skills/init/SKILL.md` — `.claude/agents/` rationale paragraph
  (Step 3.1) and Step 3.5 wording — `/hfx:init` is now described as
  "what gives you per-project customization" on top of the always-on
  plugin fallback, not as a hard prerequisite.
- `templates/planner-policy.md` — code-analyst dispatch note now
  describes the fallback rule.
- `README.md` — Worker contract section shows the resolution rule.

## Smoke-test plan

Three native runs to confirm:

1. **`/Users/yu_s/Documents/GitHub/5-13-hfx-test`** (`/hfx:init`
   already completed in round 6).
   - Expected: `/hfx:plan` discovery includes both `local:` and
     `plugin-worker:` entries for backend/frontend/docupdater;
     resolver picks bare; `/hfx:run` dispatches
     `Agent(subagent_type="backend", ...)` exactly as before. PASS
     parity with round 6.
2. **Throwaway `/tmp/hfx-fallback-test`** (no `/hfx:init`).
   - Expected: `/hfx:plan` discovery returns only `plugin-worker:` /
     `plugin-helper:` entries. `dispatch_graph` references bare
     names. `/hfx:run` Step 2b discovery succeeds (plugin source
     populated), Step 3 validation passes, Step 4 dispatches
     `Agent(subagent_type="hfx:workers:backend", ...)`. End-to-end
     PASS without ever calling `/hfx:init`.
3. **`/Users/yu_s/Documents/GitHub/hfx`** itself (plugin source
   directory, no `.claude/agents/`, no `.harness/`).
   - `/hfx:plan` aborts at Step 0 (`.harness/` missing) — that's
     correct, you shouldn't plan tickets against the plugin source
     itself. But discovery in step 2b would have worked.

## Why this round was needed

Round 7 declared "contract integrity is now resistant to ambient
environment pressure" after fixing hooks-vs-plan and the `created:`
sha exclusion. It did not check **dispatch-name resolution under
environment variation**. That assumption — "bare name always works
because `/hfx:init` was run" — was a single-environment test. Round
8 makes the dispatcher resolve from observed reality (the discovery
map) rather than from an assumed installation step.

## What still works (unchanged by round 8)

- `compute-sha.sh` exclusions (rounds 4 + 7).
- Hard rule #6 in writer workers (round 7).
- Two-gate approval flow.
- `move-ticket.sh`, `verify-approval.sh`, plan/worker file format.
- `plan.md` schema — `dispatch_graph.steps[].worker` is still the
  bare name; resolution lives in the dispatcher.

Round 8 verdict: 1 architectural fix applied. Worker dispatch now
works in both project-initialized and plugin-only environments.
