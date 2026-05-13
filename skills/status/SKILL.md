---
name: status
description: Show active hfx tickets and the next action for each. Reads .harness/tickets/active/*/plan.md frontmatter and reports ticket id, approval state, dispatch graph progress, and what /hfx command to run next. Read-only.
disable-model-invocation: true
allowed-tools: Read, Glob, Bash
---

# /hfx:status — show active tickets

## Pre-flight

```!
ls "${CLAUDE_PROJECT_DIR}/.harness/tickets/active" 2>/dev/null | head -1 || echo "EMPTY"
```

If empty, print:
> No active tickets. Run `/hfx:plan "<request>"` to create one.

Then stop.

## Read

For each subdirectory under `${CLAUDE_PROJECT_DIR}/.harness/tickets/active/`:

1. `Read` `<ticket>/plan.md` (frontmatter only — first 30 lines is enough).
2. Extract: `ticket-id`, `title`, `status`, `approved_at`, `content_sha`,
   and the `dispatch_graph.steps[].id` + `worker` list.
3. Check whether `<ticket>/results.md` exists. If yes, scan its top for
   `[succeeded]` / `[failed]` markers.

## Output format

For each ticket, print one block:

```
● <ticket-id> — <title>
  status:    draft | ready (approved) | in-progress | results-pending
  approved:  <approved_at or — not approved —>
  graph:     <step-id>(<worker>) → <step-id>(<worker>) ...
  results:   <not run | succeeded | failed: <which worker>>
  next:      <one of>
    - run /hfx:plan to finish the [a]pprove gate         (status=draft, approved_at empty)
    - run /hfx:run <ticket-id>                          (status=ready, no results.md)
    - review results.md and [a]ccept                     (results-pending)
    - investigate failure in <worker>; /hfx:plan to edit (failed)
```

End with a one-line summary: `N tickets active, M ready to run.`

## Constraints

- Do **not** modify any file.
- Do **not** dispatch any sub-agent.
- If `plan.md` is malformed (no frontmatter, missing fields), print the
  ticket id with `status: malformed` and skip the rest of the block.
