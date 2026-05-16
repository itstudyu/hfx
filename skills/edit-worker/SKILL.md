---
name: edit-worker
description: Edit an installed worker agent file based on a natural-language request. Reads .claude/agents/*.md, infers which worker the user is talking about, proposes a diff (description / tools / model / body changes), and writes only after the user approves.
disable-model-invocation: true
argument-hint: "<natural-language change request>"
allowed-tools: Read, Glob, Edit, AskUserQuestion
---

# /hfx:edit-worker — modify an installed worker

User request: `$ARGUMENTS`

## Step 1 — list workers

```!
ls "${CLAUDE_PROJECT_DIR}/.claude/agents/" 2>/dev/null
```

If empty, print:
> No installed agents in `.claude/agents/`. Run `/hfx:init` first.

Then stop.

## Step 2 — pick target

Read all `.md` files in `${CLAUDE_PROJECT_DIR}/.claude/agents/`. Match the
request against:
- the worker `name:` frontmatter
- the `description:` frontmatter
- words explicitly in `$ARGUMENTS` (e.g., "backend", "frontend")

If exactly one worker matches strongly: proceed.
If multiple match or none matches strongly: use `AskUserQuestion`
(single-select) to ask which worker. List installed workers as options.

## Step 3 — propose changes

Decide which of the four edit categories the request implies:

- **description** — frontmatter `description:` (when to invoke).
- **tools** — frontmatter `tools:` / `disallowedTools:` allowlist.
- **model** — frontmatter `model:` field.
- **body** — system prompt body (everything after the closing `---`).

Sketch the diff as a unified-diff-style block in your reply:

```
File: .claude/agents/<name>.md

@@ frontmatter @@
- model: sonnet
+ model: opus

@@ body — section "Hard rules" @@
+ 7. **New rule**: <text>
```

## Step 4 — approve

Use `AskUserQuestion`:

| header | question                                              | options |
|--------|-------------------------------------------------------|---------|
| Apply  | Apply this change?                                    | [a] apply (Recommended) / [e] edit my request / [r] reject |

- `[a] apply` → use `Edit` to apply each diff hunk. Confirm with `ls -l`.
- `[e] edit my request` → ask the user how to refine the request, then
  loop back to Step 3 with the refined intent.
- `[r] reject` → print "no changes applied" and stop.

## Output

Final message:

```
## Edited <worker>
- <category 1>: <what changed>
- <category 2>: <what changed>

## Verification
<show the resulting frontmatter and any body diff>

## Next
Run /hfx:status to see active tickets, or /hfx:plan for a new one.
```

## Hard rules

- Do not touch `name:` frontmatter (renaming a worker breaks tickets
  that reference it). If the request implies a rename, refuse and tell
  the user to remove + re-init.
- Do not edit workers under `${CLAUDE_PLUGIN_ROOT}/agents/` — those are
  read-only plugin seed templates. Only edit `${CLAUDE_PROJECT_DIR}/.claude/agents/`.
- Do not invent new frontmatter fields beyond what `agents/workers/*.md`
  documents support: `name`, `description`, `model`, `tools`,
  `disallowedTools`, `maxTurns`, `isolation`, `skills`, `memory`,
  `background`, `effort`.
