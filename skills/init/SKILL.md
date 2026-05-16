---
name: init
description: Bootstrap a project for hfx. Creates .harness/ (planner-policy, refs.yaml, memory, agents/workers/, tickets/) by asking the user which default workers to install and what model + reference docs to wire into each. Idempotent — refuses to overwrite an existing .harness/. Run once per project.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
---

# /hfx:init — bootstrap a project for hfx

You are the **planner** (the main session) acting in init mode. You will
ask the user a small number of focused questions, then create
`${CLAUDE_PROJECT_DIR}/.harness/` with the structure they chose.

## Pre-flight

1. Run:
   ```!
   ls "${CLAUDE_PROJECT_DIR}/.harness" 2>/dev/null && echo "ALREADY_EXISTS" || echo "NOT_FOUND"
   ```
2. If the output ends with `ALREADY_EXISTS`, print:
   > `.harness/` already exists in this project. Refusing to overwrite.
   > Inspect `${CLAUDE_PROJECT_DIR}/.harness/` or remove it manually first.

   Then stop. Do not ask any questions.

3. Otherwise, continue to Step 1.

## Plugin paths (use ${CLAUDE_SKILL_DIR} relative to this skill)

The plugin ships templates and default agents at:
- Templates:   `${CLAUDE_PLUGIN_ROOT}/templates/`
- Workers:     `${CLAUDE_PLUGIN_ROOT}/agents/workers/`

## Step 1 — single question, four parts (multiSelect where useful)

Use **one** `AskUserQuestion` call with these four questions:

| header        | question                                                     | multiSelect | options |
|---------------|--------------------------------------------------------------|-------------|---------|
| Workers       | Which default workers to install?                            | true        | backend / frontend / docupdater |
| code-analyst  | Install the code-analyst helper (read-only code analysis)?   | false       | yes / no |
| Policy seed   | How should planner-policy start?                             | false       | default template (Recommended) / blank skeleton |
| Refs seed     | Include example conditional entries in refs.yaml?            | false       | yes — examples (Recommended) / no — empty conditional |
| Language      | What language should plan files and worker reports be written in? | false       | English (Recommended) / 한국어 / 日本語 / Other |

Recommended defaults (first option in each): backend+frontend+docupdater
all selected; code-analyst yes; default policy; examples in refs;
English artifact language. For Language → Other, the free-form text is
passed verbatim to `planner-policy.md` §8.

## Step 2 — per-worker config

For **each** worker the user picked in Step 1, make one `AskUserQuestion`
call (sequentially — at most 3 calls total). Each call asks:

| header  | question                                              | options |
|---------|-------------------------------------------------------|---------|
| Model   | Which model should this worker use?                   | sonnet (Recommended) / opus / haiku |
| Refs    | File paths to add to refs.yaml `conditional:` (comma-separated). Skip if unsure. | <free-form via Other> |
| Policy  | One-line hint to add to planner-policy.md. Skip if unsure. | <free-form via Other> |

Capture answers in a small in-memory map keyed by worker name.

## Step 3 — generate .harness/

In one block of tool calls (parallel where independent):

1. `Bash`:
   ```
   mkdir -p "${CLAUDE_PROJECT_DIR}/.harness/memory" \
            "${CLAUDE_PROJECT_DIR}/.harness/tickets/active" \
            "${CLAUDE_PROJECT_DIR}/.harness/tickets/done" \
            "${CLAUDE_PROJECT_DIR}/.harness/tickets/trash" \
            "${CLAUDE_PROJECT_DIR}/.claude/agents"
   ```

   **Why `.claude/agents/`:** Claude Code's project-level subagent
   directory. Agents placed here are dispatchable by bare `name:`
   (no namespace prefix) and become editable per-project copies that
   `/hfx:edit-worker` can modify (model, tools, body). The plugin-shipped
   `${CLAUDE_PLUGIN_ROOT}/agents/workers/` are seed templates that
   `/hfx:run` can also dispatch directly under their namespaced names
   (`hfx:workers:<name>`) when no project-local copy exists — so the
   plugin still works without `/hfx:init`. Running `/hfx:init` is
   what gives you per-project customization on top of that fallback.

2. Read `${CLAUDE_PLUGIN_ROOT}/templates/planner-policy.md`. If user
   picked "default template", `Write` it verbatim to
   `${CLAUDE_PROJECT_DIR}/.harness/planner-policy.md`, then use `Edit`
   with `replace_all: true` to substitute `<LANG>` with the Step 1
   Language choice (verbatim, no normalization). Append per-worker
   policy hints from Step 2 under `## 9. Per-worker hints`.

   If user picked "blank skeleton", write a 10-line stub with section
   headers only.

3. Read `${CLAUDE_PLUGIN_ROOT}/templates/refs.yaml`. If user picked
   "examples", write it verbatim to `${CLAUDE_PROJECT_DIR}/.harness/refs.yaml`,
   then append any per-worker `conditional:` paths from Step 2.
   If user picked "no examples", strip the example block from `conditional:`
   first.

4. Read `${CLAUDE_PLUGIN_ROOT}/templates/memory-INDEX.md` and `Write` to
   `${CLAUDE_PROJECT_DIR}/.harness/memory/INDEX.md`.

5. For each selected worker, read
   `${CLAUDE_PLUGIN_ROOT}/agents/workers/<worker>.md` and `Write` to
   `${CLAUDE_PROJECT_DIR}/.claude/agents/<worker>.md`, overriding the
   `model:` frontmatter field with the user's choice from Step 2. With
   this project-local copy in place, `/hfx:run` will dispatch the worker
   by bare name (`Agent(subagent_type="<worker>", ...)`) and
   `/hfx:edit-worker` can modify it without touching the plugin seed.

6. If code-analyst was selected, copy
   `${CLAUDE_PLUGIN_ROOT}/agents/helpers/code-analyst.md` to
   `${CLAUDE_PROJECT_DIR}/.claude/agents/code-analyst.md`.

7. **Always copy the three reviewer workers** (no question asked):
   ```
   cp "${CLAUDE_PLUGIN_ROOT}/agents/workers/spec-reviewer.md"     "${CLAUDE_PROJECT_DIR}/.claude/agents/spec-reviewer.md"
   cp "${CLAUDE_PLUGIN_ROOT}/agents/workers/quality-reviewer.md"  "${CLAUDE_PROJECT_DIR}/.claude/agents/quality-reviewer.md"
   cp "${CLAUDE_PLUGIN_ROOT}/agents/workers/security-reviewer.md" "${CLAUDE_PROJECT_DIR}/.claude/agents/security-reviewer.md"
   ```

   **Why always:** these are not implementation workers — they are
   review meta-workers used by the dispatcher when `plan.md` frontmatter
   says `review_mode != off` or `security_review != off`. Both fields
   default to `off`, so installing the files does NOT make every ticket
   slower — they only fire on opt-in. Always installing means users
   never hit "Agent type 'spec-reviewer' not found" when they later
   enable review on a risky ticket. Per hfx's anti-self-evaluation
   principle (planner-policy.md §6), these must be available so that
   workers do not grade themselves.

## Step 4 — confirm + restart notice

Print a tree of what was created (use `Bash` `find .harness .claude/agents -maxdepth 3`)
and end with the following message **verbatim**, then STOP (do not call
any further tools, do not offer to run `/hfx:plan` yourself):

> ✅ `/hfx:init` complete.
>
> ⚠️  **Restart Claude Code before running `/hfx:plan` or `/hfx:run`.**
>
> Claude Code loads `.claude/agents/` only at session start. The workers
> just written (`backend`, `frontend`, `docupdater`, `code-analyst` —
> whichever you selected) are **not registered in this session**, so
> dispatching them by bare name will fail with `Agent type '<name>' not
> found`.
>
> Steps:
>   1. Exit this session (Ctrl+D or `/exit`).
>   2. Start a new session in this directory (`claude`).
>   3. Then: `/hfx:plan "<what you want to build>"`.
>
> (If you skip the restart, `/hfx:run` will still work via the plugin's
> `hfx:workers:<name>` fallback resolver, but `/hfx:edit-worker` and any
> per-project worker customizations will not take effect until restart.)

## Failure handling

If any Step-3 operation fails, print which step failed, what files exist
so far, and stop. Do not roll back automatically — the user may want to
inspect partial state. Suggest `rm -rf .harness` only if they confirm.
