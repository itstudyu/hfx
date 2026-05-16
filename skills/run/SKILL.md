---
name: run
description: Dispatch the workers of an approved ticket. Verifies the hard gate (approved_at + content_sha), parses plan.md dispatch_graph, runs independent workers in parallel, waits for each level before starting the next, fails fast on any worker failure, writes results.md, and offers to move the ticket to done/ + propose memory updates.
disable-model-invocation: true
argument-hint: "[ticket-id]"
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion, Agent
---

# /hfx:run — dispatch workers for an approved ticket

User argument: `$ARGUMENTS`

## Step 1 — pick the ticket

If `$ARGUMENTS` is non-empty, treat it as the ticket id.
Otherwise:

```!
ls -1t "${CLAUDE_PROJECT_DIR}/.harness/tickets/active" 2>/dev/null | head -1
```

If empty, print "No active tickets." and stop.
If exactly one, use it. Otherwise, use `AskUserQuestion` to let the user pick.

Set `TICKET_DIR = ${CLAUDE_PROJECT_DIR}/.harness/tickets/active/<ticket-id>`.

## Step 2 — hard gate verification

Use the `Bash` tool at this point — substitute the actual ticket-id
from Step 1 into the path, then run:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-approval.sh" \
         "${CLAUDE_PROJECT_DIR}/.harness/tickets/active/<actual-ticket-id-here>"

If exit ≠ 0: stop immediately and surface the script's error message
verbatim. The script tells the user exactly how to recover (re-approve,
sha mismatch, etc.). Do not bypass.

## Step 2b — discover available workers (union: project-local + plugin-shipped)

Build a discovery map from the union of two sources:

```!
{
  ls "${CLAUDE_PROJECT_DIR}/.claude/agents/" 2>/dev/null \
    | sed -n 's/\.md$//p' | awk 'NF{print "local:"$0}'
  ls "${CLAUDE_PLUGIN_ROOT}/agents/workers/" 2>/dev/null \
    | sed -n 's/\.md$//p' | awk 'NF{print "plugin-worker:"$0}'
  ls "${CLAUDE_PLUGIN_ROOT}/agents/helpers/" 2>/dev/null \
    | sed -n 's/\.md$//p' | awk 'NF{print "plugin-helper:"$0}'
} | sort -u
```

Capture this map. For each worker/helper name, note which source(s)
provide it, and resolve a single `subagent_type` per name with this
precedence (project-local always wins):

| Source(s) present                  | `subagent_type` to use         |
|-----------------------------------|---------------------------------|
| `local:<name>` (with or without plugin) | `<name>` (bare)            |
| only `plugin-worker:<name>`       | `hfx:workers:<name>`            |
| only `plugin-helper:<name>`       | `hfx:helpers:<name>`            |

Why both sources: `/hfx:init` copies plugin seeds into
`.claude/agents/` so users can edit per-project (model, tools, body).
But the plugin must also work end-to-end without `/hfx:init` —
in that case Claude Code only exposes the plugin agents under their
namespaced names (`hfx:workers:<name>`, `hfx:helpers:<name>`), and
the dispatcher must call them by that namespaced form.

If both lists are empty, abort with:
> No agents available. Either run `/hfx:init` to install
> project-local workers, or verify the plugin loaded correctly
> (`/plugin` should show hfx).

## Step 3 — parse dispatch_graph

`Read` `<TICKET_DIR>/plan.md` frontmatter. Extract `dispatch_graph.steps`:
each step has `id`, `worker`, `parallel_safe`, `depends_on`, `plan_file`.

**Validate every step.worker against the discovery map from Step 2b.**
A worker is valid if it appears as either `local:<name>`,
`plugin-worker:<name>`, or `plugin-helper:<name>`. If any step
references a worker that is not in the map, abort with:
> Plan references unavailable worker `<name>`. Either install it
> (run `/hfx:init`, or copy `${CLAUDE_PLUGIN_ROOT}/agents/workers/<name>.md`
> to `.claude/agents/<name>.md`), or edit `plan.md` to remove the
> step (and re-approve via `/hfx:plan`).

Build levels by topological sort:
- Level 0 = steps with empty `depends_on`.
- Level N = steps whose `depends_on` are all in levels < N.

A step is **parallel-launchable** in a level if `parallel_safe: true`.
Sequential (`parallel_safe: false`) steps within the same level run one
at a time inside that level.

If the graph has a cycle or references an undefined step, abort with
the cycle/undefined-id described.

## Step 4 — dispatch level-by-level

For each level in order:

1. For each step in the level, read `<TICKET_DIR>/<step.plan_file>`.
2. **Parallel block**: in **one assistant message**, emit one
   `Agent` tool call per parallel-launchable step. Resolve the
   `subagent_type` from Step 2b's discovery map per the precedence
   table — bare `<step.worker>` if a project-local copy exists at
   `.claude/agents/<step.worker>.md` (the user-editable runtime agent
   that `/hfx:init` and `/hfx:edit-worker` operate on), otherwise the
   plugin-namespaced form (`hfx:workers:<step.worker>` or
   `hfx:helpers:<step.worker>`):
   ```
   Agent(
     subagent_type="<resolved name>",
     description="<step.id> — <one-line>",
     prompt="""
You are working on ticket <ticket-id>.

<full content of plan.md>

---

<full content of <step.plan_file>>

---

Ticket directory (absolute): <TICKET_DIR>

Follow the rules in your system prompt. Report back in the exact output
format specified.
"""
   )
   ```
3. After all parallel calls in the level return, check each result:
   - If any reports failure or its summary lacks `## Tasks completed`,
     mark `step.outcome = failed` and **stop launching new levels**
     (fail-fast). Still wait for in-flight sequential steps in this
     level to finish before moving on.
   - Otherwise, mark `step.outcome = succeeded` and record the
     worker's reported `Files changed` and verification output.

## Step 5 — write results.md

After the loop ends (success or fail-fast), `Write` `<TICKET_DIR>/results.md`:

```markdown
---
ticket-id: <ticket-id>
ran_at: <ISO timestamp>
overall: succeeded | failed
---

## Per-step outcomes

### <step.id> — <worker>  [succeeded | failed]
**Files changed:**
- <path>

**Verification:**
<verbatim verification block from worker>

**Open questions:**
<worker's open questions>

(repeat per step)

## Verification (from plan.md)

- [x] <Verification item 1, checked off because <step.id> reported PASS>
- [ ] <Verification item still open>

## Next action

<one of>
- All verification items pass and overall=succeeded → review and [a]ccept.
- One worker failed → see "Open questions" / inspect the workspace.
- Verification items remain → run /hfx:plan to update plan or re-run.
```

## Step 6 — accept gate (only if overall=succeeded)

Show results.md to the user. Use `AskUserQuestion`:

| header | question                                                 | options |
|--------|----------------------------------------------------------|---------|
| Accept | Results look good — accept and move ticket to done/?     | [a] accept (Recommended) / [e] edit results.md / [r] keep in active for now |

- `[a] accept`:
   Use the `Bash` tool at this point — substitute the actual ticket-id
   from Step 1, then run:

       bash "${CLAUDE_PLUGIN_ROOT}/scripts/move-ticket.sh" \
            "${CLAUDE_PROJECT_DIR}/.harness" "<actual-ticket-id-here>" done

   Then proceed to Step 7.
- `[e]`: tell user the file path, stop.
- `[r]`: stop.

## Step 7 — memory update proposal (only if Step 6 accepted)

Re-read the worker outputs and propose 0–3 learnings that pass the test
from `planner-policy.md` §5:
- Would have saved time on **this** ticket if known beforehand.
- Non-obvious from the code alone (not findable by grep).

For each candidate, print:

```
Candidate 1: <theme>
  File: .harness/memory/<theme>.md (new | existing)
  Index line: - [<title>](<theme>.md) — <one-line hook>
  Body:
  ---
  <≤10 lines>
  ---
  [y]es / [n]o
```

Use `AskUserQuestion` per candidate (or a single multi-select if 2–4).

For each `[y]`:
- `Edit` (or `Write` if new) `.harness/memory/<theme>.md` with the body.
- `Edit` `.harness/memory/INDEX.md` to add the index line.

End with a one-line summary of what was saved.

## Failure handling

- Step 2 fail → exit, do not dispatch.
- Step 4 worker failure → fail-fast, results.md still written with
  `overall: failed`, no Step 6, no Step 7. Ticket remains in `active/`
  for inspection.
- Step 5–7 file write failures → print which write failed; user can
  recover by re-running `/hfx:run` (Step 2 will pass since plan didn't
  change, Step 4 will re-dispatch — workers should be idempotent).
