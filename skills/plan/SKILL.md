---
name: plan
description: Plan a new ticket. Loads planner-policy + refs.yaml + memory index, grills the user one question at a time with AskUserQuestion (Tier 1/2/3 escalation), drafts plan.md + plan.<worker>.md inside a new active/ ticket directory, and walks the user through two approval gates (sync → plan) — the second gate fills approved_at + content_sha so /hfx:run can verify integrity.
disable-model-invocation: true
argument-hint: "<your request>"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, AskUserQuestion, WebFetch, WebSearch, Agent
---

# /hfx:plan — grill and draft a plan

User request: `$ARGUMENTS`

You are the **planner** (the main session) acting as the central planner.
Your job in this skill is to reach sync with the user, draft plan files,
and gate them through two approvals.

## Step 0 — pre-flight

```!
ls "${CLAUDE_PROJECT_DIR}/.harness/planner-policy.md" 2>/dev/null && echo "READY" || echo "MISSING"
```

If `MISSING`:
> `.harness/` is not initialized. Run `/hfx:init` first.

Then stop.

If `$ARGUMENTS` is empty:
> `/hfx:plan` needs a request. Example: `/hfx:plan "Add a /health endpoint"`.

Then stop.

## Step 1 — load context

In one block of `Read` calls (parallel):
- `${CLAUDE_PROJECT_DIR}/.harness/planner-policy.md`
- `${CLAUDE_PROJECT_DIR}/.harness/refs.yaml`
- `${CLAUDE_PROJECT_DIR}/.harness/memory/INDEX.md`

Then parse `refs.yaml`:
- Read every `always:` path.
- For each `conditional:` entry, lowercase-match its `keywords` against
  the lowercased `$ARGUMENTS`. If any keyword matches, `Read` the path.
- `manual:` entries are loaded only if the user named them in `$ARGUMENTS`
  (e.g., includes `[refs:docs/security.md]`).

If any referenced path is missing, note it but do not abort.

### Active memory retrieval (planner-policy §5 read side)

After loading INDEX.md, do a deterministic keyword match between
`$ARGUMENTS` (lowercased) and each INDEX line:

```
keywords = lowercase($ARGUMENTS).split()
matches  = []
for line in INDEX.md:
  hook = lowercase(line)
  hits = count(k in hook for k in keywords)
  if hits >= 1:
    matches.append((hits, theme_file_from_line))
top_3 = matches.sort_by(hits desc).take(3)
```

`Read` each of the top 1–3 theme files (parallel block). Use the
contents during grilling so the planner doesn't re-ask things already
learned. If 0 matches → skip; the index alone is enough.

## Step 2 — discover available workers (union: project-local + plugin-shipped)

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

Build a discovery map keyed by name. The dispatch graph can only
reference names that appear in this map. Treat `code-analyst` (and
anything else under `agents/helpers/`) as a helper, not a worker —
never put helpers in `dispatch_graph`.

`/hfx:run` will resolve each name to a `subagent_type` at dispatch
time using this precedence (project-local always wins):

| Source(s) present                  | `subagent_type`             |
|------------------------------------|------------------------------|
| `local:<name>`                     | `<name>` (bare)              |
| only `plugin-worker:<name>`        | `hfx:workers:<name>`         |
| only `plugin-helper:<name>`        | `hfx:helpers:<name>`         |

You don't need to encode the resolution into `plan.md` — record only
the bare worker name in `dispatch_graph.steps[].worker`. The
dispatcher does the resolution.

## Step 3 — initial intake (no questions yet)

Re-read `$ARGUMENTS` and decide which decision tier the request lives at
(planner-policy §1):
- If the request is unambiguous and the work is small: skim it to one
  candidate plan, then jump to Step 5 (propose, do not grill).
- If anything is unclear, large, or scope-ambiguous: begin grilling in
  Step 4.

State your read aloud in 2–4 sentences: "Here's what I think you want,
here's what's unclear." Then ask the user to confirm before drilling in.

## Step 4 — grilling loop

Walk down the decision tree, **one** `AskUserQuestion` at a time. Apply
planner-policy §1 (Mechanical / Taste / User Challenge).

Between questions:
- If a question would be answered by reading code, **read the code**
  instead of asking.
- If reading would flood your context (you'd open more than ~5 files):
  ```
  Agent(
    subagent_type="<resolved code-analyst name>",
    description="<one-line scope>",
    prompt="<a single specific question + scope hint>"
  )
  ```
  Resolve `<resolved code-analyst name>` from Step 2's discovery map:
  use bare `code-analyst` if a project-local copy exists at
  `.claude/agents/code-analyst.md` (installed by `/hfx:init`),
  otherwise use `hfx:helpers:code-analyst` (plugin-shipped). Use the
  returned summary; do not re-read.
- For external library/API docs: use `WebFetch` / `WebSearch` directly.

Stop grilling when:
- All Tier-3 (User Challenge) decisions are made.
- All Tier-2 (Taste) decisions are made or the user has explicitly
  deferred them to you.
- Tier-1 (Mechanical) decisions you handle silently are listed in your
  draft.

## Step 5 — sync gate

State the plan in conversational prose (no file yet):

```
SYNC

Goal: <one-line, verifiable>
Workers: <list, e.g., backend, docupdater>
Dispatch: <which run in parallel, which are sequential>
Out of scope: <bullet list>
Verification: <bullet list of checkable items>
```

Use `AskUserQuestion` (single):

| header | question                       | options |
|--------|--------------------------------|---------|
| Sync   | 이 sync 그대로 진행할까요?      | [a] approve — write plan files (Recommended) / [e] edit sync / [q] I have a question / [r] reject and discard |

- `[a]` → Step 6.
- `[e]` → return to Step 4, ask for the specific refinement.
- `[q]` → answer the user's question, then re-show the sync block.
- `[r]` → no plan files created yet, just print:
  > Ticket discarded before creation. Run `/compact` to clear this
  > planning context, then `/hfx:plan` again.

## Step 6 — draft plan files

Generate `ticket_id` as `<YYYY-MM-DD>-<kebab-slug-of-title>`. Use today's
date in the user's local zone if known; otherwise UTC. Slug ≤ 40 chars.

Set `TICKET_DIR = ${CLAUDE_PROJECT_DIR}/.harness/tickets/active/<ticket-id>`,
substituting the actual generated ticket-id.

Use the `Bash` tool at this point — substitute the actual generated
ticket-id into the path, then run:

    mkdir -p "${CLAUDE_PROJECT_DIR}/.harness/tickets/active/<actual-ticket-id-here>"

`Read` the two templates:
- `${CLAUDE_PLUGIN_ROOT}/templates/plan.md.tmpl`
- `${CLAUDE_PLUGIN_ROOT}/templates/plan.worker.md.tmpl`

For each `__PLACEHOLDER__`, substitute. Build the `dispatch_graph.steps:`
list from the sync (one entry per worker that has actual work).

`Write`:
- `<TICKET_DIR>/plan.md` (frontmatter: `status: draft`,
  `approved_at: null`, `content_sha: null`, `review_mode: off`,
  `security_review: off`)
- `<TICKET_DIR>/plan.<worker>.md` for every worker in the graph.

Print a tree of what was written.

## Step 6.5 — risk signal scan + review-mode proposal (opt-in question)

Apply planner-policy §4a — see that section for the full signal table
(path-match + keyword-match per signal). Compute the risk signals from
the just-written plan files by greping the union of:
(a) every path listed in `## Files manifest` / `## Reference files`, and
(b) the natural-language text of `## Goal` and `## Tasks`.

A signal fires if EITHER (a) or (b) matches. See planner-policy.md §4a
for the exact patterns. Quick summary:

- `worker_count` = entries in `dispatch_graph.steps`
- `touches_auth`: paths `auth*|login*|session*|token*|jwt*|oauth*` OR keywords `auth, login, session, token, jwt, oauth, password, sso, sign-in`
- `touches_secrets`: paths `.env|secrets|*.pem|credentials` OR keywords `secret, credential, api key, private key`
- `touches_ci`: paths `.github/workflows|Dockerfile|.gitlab-ci|buildspec` OR keywords `workflow, pipeline, dockerfile, ci/cd`
- `touches_prompts`: paths `agents/*.md|.claude/agents/|skills/*/SKILL.md|templates/*.md` OR keywords `prompt, agent, subagent, system prompt, worker`
- `touches_public_api`: keywords `endpoint, route, public api, exported, breaking change, migration`

Derive recommendations (see planner-policy §4a for the exact rule table).

**If both recommendations are `off` → SKIP this step entirely.** Proceed
to Step 7. The whole point of opt-in is that 80–90% of tickets see no
extra question here.

**If either recommendation is non-`off`**, use ONE `AskUserQuestion`:

| header | question | options |
|--------|----------|---------|
| Review | ⚠️ <reason>. Suggested: review_mode=<X>, security_review=<Y>. | [a] approve recommendation (Recommended) / [m] max — strict + full / [n] keep both off (speed-only) / [e] customize each axis |

Where `<reason>` is a short phrase like "touches auth surface" or
"multi-worker change with public API".

Branch handling:
- `[a]` → write the recommended values into `plan.md` frontmatter (use `Edit`).
- `[m]` → write `review_mode: strict`, `security_review: full` (most thorough; biggest LLM cost).
- `[n]` → leave both at `off`.
- `[e]` → ask two follow-up AskUserQuestion calls, one per axis:
   1. `review_mode?` → [strict] / [lenient] / [off]
   2. `security_review?` → [full] / [diff] / [off]
   Then write the chosen values.

After writing, proceed to Step 7. (Sha will be computed on `[a]` at the
plan gate; the frontmatter values are part of the locked content.)

## Step 7 — plan gate

Show the user the rendered file paths and the **full text** of `plan.md`
(and a one-line per `plan.<worker>.md` summary). Use `AskUserQuestion`:

| header | question                                  | options |
|--------|-------------------------------------------|---------|
| Plan   | Plan 파일들 그대로 승인할까요?              | [a] approve — fill approved_at + content_sha (Recommended) / [e] edit plan files / [q] I have a question |

- `[a]` →
   1. Use the `Bash` tool at this point — substitute the actual
      ticket-id from Step 6 into the path, then run:

          bash "${CLAUDE_PLUGIN_ROOT}/scripts/compute-sha.sh" \
               "${CLAUDE_PROJECT_DIR}/.harness/tickets/active/<actual-ticket-id-here>"

      The script prints a 64-char hex digest on stdout. Capture it.
   2. `Edit` `<TICKET_DIR>/plan.md` frontmatter:
      - `status: ready`
      - `approved_at: <current ISO timestamp>`
      - `content_sha: <sha from step 1>`
   3. Print:
      > Approved (ticket `<actual-ticket-id>`, sha `<first-8-chars>`).
   4. Proceed directly to Step 8 (handoff). Do **not** print a
      "Next: `/hfx:run`" line here — Step 8 prints it as part of the
      ticket summary.
- `[e]` → ask which file/section. Use `Edit` to update. Then loop back
  to Step 7 (sha will be recomputed on the next [a]).
- `[q]` → answer, then re-present Step 7.

## Step 8 — handoff

Print the ticket summary and end with a single `Next:` line. **Do not
ask another AskUserQuestion** — the plan gate already concluded.

```
## Ticket created
- id:     <ticket-id>
- status: ready
- files:
  - .harness/tickets/active/<ticket-id>/plan.md
  - .harness/tickets/active/<ticket-id>/plan.<worker>.md  (× N)

Next: `/hfx:run <actual-ticket-id>`
```

Then STOP.

**Why no question here:** earlier versions asked "지금 /hfx:run
실행할까요? [y]/[n]" but `[y]` only prints the exact command for the
user to paste — `/hfx:run` is `disable-model-invocation: true` and
cannot be auto-invoked. The question added a click without adding
value: the user types `/hfx:run` either way. A bare `Next:` line is
faster.

## Hard rules

- **Never** generate `content_sha` by guessing — only the
  `compute-sha.sh` script's output is acceptable.
- **Never** set `approved_at` without the user explicitly choosing `[a]`
  at the Step-7 gate.
- **Never** dispatch a worker from this skill — that is `/hfx:run`'s job.
- **Never** modify files outside `<TICKET_DIR>` and (with user consent)
  `.harness/memory/*` after Step 8 ends.
- Plan files must reference only workers that appear in Step 2's
  discovery map (project-local **or** plugin-shipped). If the sync
  needs a worker that is in neither, stop and tell the user to install
  it via `/hfx:init`, or to drop a custom worker file at
  `${CLAUDE_PLUGIN_ROOT}/agents/workers/<name>.md` /
  `.claude/agents/<name>.md` and re-run `/hfx:plan`.
