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
| Workers       | 어떤 default worker를 설치할까요?                            | true        | backend / frontend / docupdater |
| code-analyst  | code-analyst helper(읽기 전용 코드 분석)를 설치할까요?       | false       | yes / no |
| Policy seed   | planner-policy를 어떻게 시작할까요?                          | false       | default template (Recommended) / blank skeleton |
| Refs seed     | refs.yaml에 예시 conditional 항목을 포함할까요?              | false       | yes — examples (Recommended) / no — empty conditional |

Recommended defaults (first option in each): backend+frontend+docupdater
all selected; code-analyst yes; default policy; examples in refs.

## Step 2 — per-worker config

For **each** worker the user picked in Step 1, make one `AskUserQuestion`
call (sequentially — at most 3 calls total). Each call asks:

| header  | question                                              | options |
|---------|-------------------------------------------------------|---------|
| Model   | 이 worker가 쓸 model?                                 | sonnet (Recommended) / opus / haiku |
| Refs    | refs.yaml `conditional:`에 추가할 파일 경로 (콤마 분리). 모르면 skip. | <free-form via Other> |
| Policy  | planner-policy.md에 추가할 한 줄 hint. 모르면 skip.    | <free-form via Other> |

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
   `${CLAUDE_PROJECT_DIR}/.harness/planner-policy.md`, then append any
   per-worker policy hints from Step 2 under a new `## 8. Per-worker hints`
   section.
   If user picked "blank skeleton", write a 10-line stub with only the
   section headers (no body).

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

## Step 4 — confirm

Print a tree of what was created (use `Bash` `find .harness .claude/agents -maxdepth 3`)
and end with:

> Ready. Next: `/hfx:plan "<what you want to build>"`.

## Failure handling

If any Step-3 operation fails, print which step failed, what files exist
so far, and stop. Do not roll back automatically — the user may want to
inspect partial state. Suggest `rm -rf .harness` only if they confirm.
