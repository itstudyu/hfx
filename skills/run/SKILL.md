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
1a. **Capture pre-dispatch SHA per step** (required for Step 4a diff):
    ```!
    git rev-parse HEAD
    ```
    Record the output as `step.base_sha`. This is the diff base the
    reviewers will compare against. Do this BEFORE the Agent call, in
    the same project working tree (not in any worktree — workers in
    `isolation: worktree` will branch from this commit).
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
     isolation="worktree",  # only when worker frontmatter has `isolation: worktree`
     description="<step.id> — <one-line>",
     prompt="""
You are working on ticket <ticket-id>.

<full content of plan.md>

---

<full content of <step.plan_file>>

---

Ticket directory (absolute): <TICKET_DIR>

Follow the rules in your system prompt. Your final message MUST contain a `## Status` line with one of: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT.
"""
   )
   ```
3. After all parallel calls in the level return, parse each result's
   `## Status` line and branch:

   | Status | Treat as |
   |--------|----------|
   | `DONE` | succeeded — proceed to 4a |
   | `DONE_WITH_CONCERNS` | succeeded — proceed to 4a, but flag concerns in results.md |
   | `BLOCKED` | failed — fail-fast, stop launching new levels |
   | `NEEDS_CONTEXT` | failed — surface the worker's question to user; stay in `active/` |

   **Missing-verdict handling:** if `## Status` is absent, do NOT
   silently fall back to "`## Tasks completed` present → succeeded."
   That fallback masked a mid-turn truncation in
   `2026-05-17-login-page-mock`. Instead:
   - Set `step.outcome = needs_attention`.
   - Set `step.notes = "worker_no_status_verdict"`.
   - In `results.md`, under the step's section, add a top-line warning:
     `⚠ Worker did not emit ## Status; planner must verify manually
     before accepting.`
   - Continue to Step 4.5 (hand-off) and Step 4a (reviewers) so the
     work is still inspectable, but Step 6's accept gate refuses
     `[a]ccept` unless the user explicitly types `accept-no-status`
     in the Other field.

   When a step fails, still wait for in-flight sequential steps in this
   level to finish before moving on (don't kill them mid-run, but don't
   start new levels).

   For each succeeded step, record the worker's reported `Files changed`
   and verification output, then proceed to Step 4.5 (worktree hand-off)
   **before** Step 4a, for **each succeeded step in this level**, before
   moving to the next level.

## Step 4.5 — worktree hand-off (per succeeded step, no user questions)

**Why this step exists.** Workers whose agent file declares
`isolation: worktree` run inside `.claude/worktrees/agent-<id>/`. Their
`Edit`/`Write` operations land in the worktree, not in the main project
tree. Without this step the worker reports `DONE` but `git status` in
the main project shows nothing — confusing the user and breaking
downstream reviewers that diff against the main project HEAD.

This step copies the worker's allow-listed output from the worktree
back to the main project root using `scripts/handoff-worktree.sh`. The
allow-list is the worker plan's `Files manifest` (Create + Modify
entries) — anything the worker touched outside that list is reported
as `out_of_scope`, never copied.

### 4.5.1 — Skip if not a worktree worker

Read the worker's resolved agent file (from Step 2b's discovery map)
and grep its frontmatter for `isolation: worktree`. If absent, skip
this entire step — the worker wrote directly to the main tree.

### 4.5.2 — Detect the worktree path

The `Agent` tool returns the worktree path and branch in its result
when changes were made (see the system-prompt note: *"With
`isolation: \"worktree\"`, the worktree is automatically cleaned up
if the agent makes no changes; otherwise the path and branch are
returned in the result."*). Parse the worktree path from the agent
result. If the agent result does not contain a worktree path, fall
back to scanning `.claude/worktrees/` for the most recently modified
`agent-*` directory whose branch matches the agent's reported branch.

If neither yields a worktree path, log it in `step.notes` and skip
the rest of 4.5 — the worker either ran without isolation despite
the frontmatter, or made no changes (a no-op success).

### 4.5.3 — Extract the allow-list from plan.\<worker\>.md

Parse `<TICKET_DIR>/<step.plan_file>` `## Files manifest` section.
Collect every path under `**Create:**` and `**Modify:**` bullets. Skip
`**Test:**` only if the worker is not a test author. (If the manifest
literally says "(none — empty project)", the allow-list is empty and
this step degrades to a no-op that just reports `out_of_scope` for
everything the worker actually touched — fail-fast surfaces the
scope mismatch.)

Write the paths, one per line, to a temp file. Use the `Bash` tool
(NOT a `!` preprocess fence — the paths come from runtime parsing of
the worker plan, so substitution must happen at execution time):

```bash
# After substituting the actual parsed paths (one per Create/Modify
# entry), run via the Bash tool. The example below uses placeholder
# paths; replace them with the real paths from Step 4.5.3's parse.
TMP_MANIFEST="$(mktemp)"
printf '%s\n' \
  "<path-1-from-parsed-manifest>" \
  "<path-2-from-parsed-manifest>" \
  > "$TMP_MANIFEST"
echo "$TMP_MANIFEST"
```

Capture the printed temp-file path as `TMP_MANIFEST` for 4.5.4 / 4.5.6.

### 4.5.4 — Run the hand-off script

**Hard precondition.** Before running anything, verify ALL THREE:

1. The worktree path (from 4.5.2) is non-empty AND `test -d` passes
   on it.
2. The `TMP_MANIFEST` file (from 4.5.3) is non-empty AND contains
   at least 1 non-blank, non-comment line.
3. The Agent result from Step 4 reported `## Status: DONE` or
   `## Status: DONE_WITH_CONCERNS`.

If ANY check fails, do NOT call the script. Record
`step.handoff = {"skipped": "<reason>"}` (e.g. `"no_worktree_detected"`,
`"empty_manifest"`, `"worker_blocked"`) and jump directly to 4.5.6.

Use the `Bash` tool (NOT a `!` preprocess fence — the worktree path
and manifest file path come from runtime steps 4.5.2 / 4.5.3 and
must be substituted at execution time):

```bash
# Substitute <worktree-dir> with the path from 4.5.2 and
# <TMP_MANIFEST> with the temp file path from 4.5.3, then run via
# the Bash tool. Do NOT put this in a !-fence — the values are
# unknown until runtime.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-worktree.sh" \
     "<worktree-dir>" \
     "${CLAUDE_PROJECT_DIR}" \
     "<TMP_MANIFEST>"
```

The script prints a single JSON line to stdout:

```
{"copied":[...],"skipped_same":[...],"conflicts":[...],"out_of_scope":[...]}
```

Capture it as `step.handoff`.

### 4.5.5 — Branch on the result

| Field          | Meaning                                                         | Action |
|----------------|-----------------------------------------------------------------|--------|
| `copied`       | Files newly landed in the main tree                             | record as the canonical landed paths |
| `skipped_same` | Files already identical in the main tree (idempotent re-run)    | record as landed too |
| `conflicts`    | Files exist in main tree with different content — **NOT** overwritten | **fail the step** |
| `out_of_scope` | Files the worker touched that are not in the manifest           | **fail the step** (scope creep) |

If `conflicts` is non-empty: mark `step.outcome = failed`, record the
conflict list in `step.handoff_findings`, and treat as a fail-fast event
(no Step 4a, results.md gets `overall: failed`). The user must reconcile
the conflict manually — copying the worker's version over a divergent
main-tree file would silently destroy user changes.

If `out_of_scope` is non-empty: mark `step.outcome = failed` with
`step.handoff_findings` listing each path. The worker exceeded its plan;
this is the same class of violation as a reviewer's `OUT_OF_SCOPE`
finding (spec-reviewer Hard rule #5) and gets the same treatment.

Otherwise (only `copied` and `skipped_same`): the landed paths replace
the worker's worktree-relative paths everywhere downstream. Update
`step.files_changed` to the union of `copied` + `skipped_same`. These
are the paths reviewers and results.md will see.

### 4.5.6 — Clean up the temp manifest

Use the `Bash` tool (NOT a `!` preprocess fence — `TMP_MANIFEST` is a
runtime value). If 4.5.3 was skipped (precondition failed in 4.5.4),
there is no temp file to remove; skip this step too:

```bash
# Substitute <TMP_MANIFEST> with the path from 4.5.3, then run via
# the Bash tool. Safe to skip if TMP_MANIFEST was never created.
rm -f "<TMP_MANIFEST>"
```

(The worktree itself is not deleted — Claude Code manages worktree
lifecycle, and leaving it lets the user diff against the worktree if a
later step needs forensics.)

## Step 4a — review loop (per succeeded step, no user questions)

Read `plan.md` frontmatter to get `review_mode` and `security_review`
(default to `off` if absent — backward-compat with v0.0.4 plans).

For each step that just completed with `step.outcome = succeeded`:

### 4a.1 — Determine the file set for review

After Step 4.5 hand-off, the canonical set of changed files is
`step.files_changed` (copied + skipped_same from the hand-off result).
These paths are guaranteed to exist in the main project tree.

- `BASE_SHA = step.base_sha`  (from Step 4.1a)
- `HEAD_SHA = git rev-parse HEAD`  (in the main project)
- `FILES   = step.files_changed`  (main-tree-relative paths landed by 4.5)

The reviewer compares `FILES` against `BASE_SHA`. If the worker
committed inside the worktree (rare), `HEAD_SHA` will have advanced;
otherwise `FILES` are still untracked/modified in the main tree and the
reviewer reads them directly (the worker plan's expected content is
the authoritative spec, not commit state).

If `step.files_changed` is empty (worker reported success but Step 4.5
copied nothing — typically a docs-only or refactor-in-place worker
whose `Files manifest` was `(none)`): skip reviewers and record the
oddity in `step.notes`.

For workers without `isolation: worktree` (i.e., Step 4.5 was skipped),
fall back to the v0.0.5 behavior: `FILES = worker-reported Files changed`
from the agent return, paths resolved against the main project root.

### 4a.2 — Dispatch spec-reviewer (if review_mode ∈ {lenient, strict})

Resolve `subagent_type` from the Step 2b discovery map: bare
`spec-reviewer` if present locally, else `hfx:workers:spec-reviewer`.

```
Agent(
  subagent_type="<resolved>",
  description="spec review — <step.id>",
  prompt="""
You are reviewing the just-completed work for step <step.id>.

<full content of plan.md>

---

<full content of plan.<worker>.md>

---

Files landed in the main project tree (canonical — these are the paths
to review; the worker may have originally written them inside an
isolated worktree, but Step 4.5 hand-off has copied them to the main
project root and verified they match the worker plan's Files manifest):
<step.files_changed>

Ticket directory: <TICKET_DIR>
Project root:     <CLAUDE_PROJECT_DIR>
BASE_SHA: <step.base_sha>
HEAD_SHA: <see 4a.1>

Follow your system prompt. Your final message MUST start with `## Spec review result` followed by `SPEC_PASS` or `SPEC_FAIL` on the next line. No prose before this header.
"""
)
```

- If `SPEC_PASS` → proceed to 4a.3.
- If `SPEC_FAIL` → enter the fix loop (4a.4) with the reviewer's findings.
- If neither verdict line appears → mark `step.outcome = failed`, `step.notes = "reviewer_no_verdict"`. **Never perform the review inline in the main session.**

After the reviewer returns (PASS or FAIL), `Write` the reviewer's
verbatim final-message body (markdown, as emitted — no JSON wrapping)
to:

  `<TICKET_DIR>/spec-report.<step.id>.md`

If the file already exists (re-run of `/hfx:run` on the same ticket),
overwrite. `r<round>` suffixes are deferred to v0.0.6 (no auto-fix
loop in v0.0.5; rounds are user-driven and the user can `git mv` to
preserve history).

### 4a.3 — Dispatch quality-reviewer (only if review_mode == strict)

Same dispatch shape as 4a.2 but with `subagent_type` resolving to
`quality-reviewer`, and include the SPEC_PASS summary in the prompt
context (so it knows spec is already verified).

- If `QUALITY_PASS` → proceed to 4a.5 (security branch).
- If `QUALITY_FAIL` → enter the fix loop (4a.4) with the findings.

After the reviewer returns, `Write` the same shape to
`<TICKET_DIR>/quality-report.<step.id>.md`. Same overwrite rule as
spec-report.

### 4a.4 — Review FAIL handling (no auto-fix in v0.0.5)

If a reviewer returns FAIL:

1. Mark `step.outcome = failed`.
2. Record the reviewer's findings in `step.review_findings`.
3. Stop launching new levels (fail-fast). Ticket stays in `active/`.
4. Surface the findings in `results.md` Step 5 under the step's
   `Review:` section so the user can act on them.

**Why no auto-fix loop:** v0.0.5 intentionally does NOT re-dispatch the
implementer with reviewer findings. Reasons:

- `isolation: worktree` creates a NEW worktree per `Agent` call —
  there is no plugin-level mechanism to force a re-dispatch into the
  *same* worktree, so a second attempt would not see the first
  attempt's changes.
- Reviewer findings are untrusted text. Threading them back into the
  implementer's prompt could silently widen scope past the sha-locked
  `plan.<worker>.md` (e.g., a reviewer suggestion that says "also edit
  file Z to fix this" gets applied with no re-approval).
- hfx's principle: code never moves without a human signature. The
  user's `[a]ccept` gate is the right place to decide whether
  reviewer-found issues block, get filed as follow-up tickets, or are
  accepted as-is.

The user can fix manually in the worktree, re-run `/hfx:plan` to
amend, or accept the failed step's findings and move on.

### 4a.5 — Dispatch security-reviewer (if security_review ∈ {diff, full})

Only after all other reviewers in this step have passed (or were
skipped). Resolve `subagent_type` to `security-reviewer`.

```
Agent(
  subagent_type="<resolved>",
  description="security review — <step.id>",
  prompt="""
You are reviewing the just-completed work for step <step.id>.

scope: <diff | full>   ← from plan.md frontmatter

<full content of plan.md>

---

<full content of plan.<worker>.md>

---

Files landed in the main project tree (canonical paths after Step 4.5
hand-off; review these against BASE_SHA):
<step.files_changed>

Ticket directory: <TICKET_DIR>
Project root:     <CLAUDE_PROJECT_DIR>
BASE_SHA: <pre-dispatch SHA>
HEAD_SHA: <post-dispatch SHA>

Follow your system prompt. Apply the 8/10 confidence gate. Emit the
JSON report block — the dispatcher will save it.
"""
)
```

If the agent returns a fenced ```json``` block, `Write` it to:
```
<TICKET_DIR>/security-report.<step.id>.json
```

- If `SECURITY_PASS` → step is fully done; proceed to next step.
- If `SECURITY_FAIL` → mark `step.outcome = failed`, record the findings,
  and stop launching new levels (fail-fast). Ticket stays in `active/`.

**Security findings do NOT enter the fix loop.** Auto-fixing security
issues without human review is too dangerous. The ticket pauses and
surfaces the report for the user to inspect.

### 4a.6 — Skip-all path (review_mode == off AND security_review == off)

If both are `off`, do nothing in Step 4a. Step 4's `step.outcome = succeeded`
is final. This is the speed-first default path that 80–90% of tickets take.

### 4a.7 — Planner-applied fixes (user-initiated)

If reviewers FAILED and the user picks "apply the fix manually via
planner" (Step 5 results.md `Next action` option 1), the planner
applies the edits **in the main project tree** (not in the worker's
worktree — that may have been cleaned up). This flow is user-initiated
and explicit; it is NOT auto-fix (Step 4a.4 still holds: the planner
never re-dispatches workers with reviewer findings on its own).

Two rules govern these edits:

1. **Hook conflicts.** If a `PostToolUse` hook (e.g. user-global
   `code-quality-check`) blocks an edit that implements a behavior the
   plan explicitly specifies, the planner does NOT appease the hook.
   Identification: the tool-result contains hook stderr matching a
   `~/.claude/settings.json` `hooks.PostToolUse.*.command` name.
   Bypass test: the flagged code (literal token or behavior) appears
   verbatim in `plan.<worker>.md ## Tasks` for the failing step.
   Quote the matching task line when recording the conflict in
   `results.md ## Open questions`. This mirrors workers' hard rule #6.

2. **Scope.** The planner only touches files in
   `step.files_changed` (the post-handoff manifest). Touching new
   files at fix-time is scope creep — escalate to a new ticket
   instead.

After all fixes are applied, the planner re-runs reviewers (Step 4a.2
and 4a.3 only — security re-runs only if quality re-passes). spec /
quality reports are overwritten per 4a.2 / 4a.3 persistence rules.

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
- <path>   (landed at this path in the main project root)

**Hand-off:** <one of>
- `n/a` — worker did not use `isolation: worktree`
- `clean` — all files copied or already identical (worktree → main)
- `conflicts: <list>` — main tree had divergent content; step failed
- `out_of_scope: <list>` — worker touched files outside its manifest; step failed

**Verification:**
<verbatim verification block from worker>

**Review:**
<if review_mode == off>  skipped
<else>  spec=<PASS|FAIL>, quality=<PASS|FAIL|n/a if lenient>
        <if any FAIL: paste reviewer's findings block verbatim>

**Security:**
<if security_review == off>  skipped
<else>  result=<PASS|FAIL>  scope=<diff|full>
        report: <TICKET_DIR>/security-report.<step.id>.json

**Open questions:**
<before writing this block, check <TICKET_DIR>/declined-skills.json.
If the file exists, prepend its contents (one entry per item) as
`[skill-declined]` entries:
  [skill-declined] /frontend-design — declined at plan time because
  <reason>. User confirmed via [a] approve at the planner-policy §9
  re-frame gate. Channel: <chat|askuserquestion-other|args>.>
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

Re-read the worker outputs and propose 0–3 learnings that pass **all
three gates** from `planner-policy.md` §5 step 2:

1. **Saves future time** — would have saved time on this very ticket
   if known beforehand.
2. **Non-obvious from code** — would not be found by a `grep` over the
   project files.
3. **Permanent, not a workaround** — describes a permanent solution,
   not a temporary workaround for a bug. If a candidate fails this
   gate, drop it and suggest the user file a bug ticket instead.

For each surviving candidate, print the exact file that will be
written, using the structure from `planner-policy.md` §5 step 3:

```
Candidate 1: <theme>
  File: .harness/memory/<theme>.md (new | existing)
  Index line: - [<title>](<theme>.md) — <one-line hook>
  Body (written verbatim — YAML frontmatter + 5-line skeleton):

      ---
      files:
        - <repo-relative path>
      ---

      Problem: <one line>
      Cause:   <one line>
      Fix:     <one line>
      Why:     <one line>
      When-not-to-apply: <the explicit expiry condition for this learning>

  [y]es / [n]o
```

The candidate MUST already contain the frontmatter + 5-line skeleton
when shown to the user — do not show free-form prose and then "fix it
into the skeleton" after [y]. If you cannot fit the learning into the
skeleton (especially the `When-not-to-apply:` line), the learning is
too vague — drop the candidate.

Use `AskUserQuestion` per candidate (or a single multi-select if 2–4).

For each `[y]`:
- `Edit` (or `Write` if new) `.harness/memory/<theme>.md` with the body
  exactly as shown.
- `Edit` `.harness/memory/INDEX.md` to add the index line.

End with a one-line summary of what was saved.

## Failure handling

- Step 2 fail → exit, do not dispatch.
- Step 4 worker failure → fail-fast, results.md still written with
  `overall: failed`, no Step 6, no Step 7. Ticket remains in `active/`
- Step 4.5 hand-off failure (conflicts or out_of_scope) → mark
  `step.outcome = failed`, write `results.md` with `overall: failed` and
  the `Hand-off:` block populated with the conflict / out_of_scope list,
  skip Step 4a (no review of unlanded files), skip Step 6/7. Ticket stays
  in `active/`. The user resolves by either reconciling the conflict
  manually (then re-running `/hfx:run`, which is idempotent on Step 4.5)
  or by editing the plan to expand the manifest and re-approving via
  `/hfx:plan`.
  for inspection.
- Step 5–7 file write failures → print which write failed; user can
  recover by re-running `/hfx:run` (Step 2 will pass since plan didn't
  change, Step 4 will re-dispatch — workers should be idempotent).
