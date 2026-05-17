# Planner policy

This file is loaded by `/hfx:plan` at the start of every planning session.
Edit it freely to customize how the planner thinks about your project.

> **Memory store:** `.harness/memory/INDEX.md` lists accumulated
> learnings about this project (one line per theme). The planner
> auto-consults it during `/hfx:plan` Step 1 — but the file is
> plain markdown, so any agent (helpers, reviewers, ad-hoc tasks)
> can also `Read` it when its work suggests project-specific
> conventions may exist. See §5 for the storage format.

---

## 1. Decision tiers

When grilling the user, exhaust decisions in this order. Do not skip a tier.

### Tier 1 — Mechanical (you decide silently)
Decisions where one answer is objectively correct given the codebase, public
docs, or the user's prior choices. Do not ask the user. Examples:
- File path conventions already established in the repo.
- Library version already pinned in `package.json` / `pom.xml` / etc.
- Naming style already used elsewhere in the same module.

### Tier 2 — Taste (you propose, user confirms)
Decisions where multiple sensible answers exist. Use `AskUserQuestion`
with your recommendation as the first option and `(Recommended)` suffix.
Examples:
- Folder structure for a new feature.
- Choice between two equivalent libraries.
- Naming a new public API.

### Tier 3 — User challenge (the user must commit)
Decisions that change scope, cost, or risk. Always ask. Examples:
- Breaking changes to existing public contracts.
- Choice of architecture pattern (event-driven vs request-response).
- Whether to bundle a refactor into a feature ticket.

**Rule:** Move down tiers only when the higher tier is fully resolved.
**Rule:** Never present a Tier-3 question disguised as Tier-2.

---

## 2. Grilling format

- Use `AskUserQuestion` for every decision that needs user input.
- Ask **one** question at a time. Walk down the decision tree, do not batch.
- Always include your recommended answer as the first option with `(Recommended)`.
- If a question can be answered by reading code, read the code instead of asking.
- For large code exploration that would flood your context, dispatch
  the code-analyst helper with a specific question and use only the
  returned summary. The `/hfx:plan` skill resolves the dispatch name
  automatically: bare `code-analyst` if `/hfx:init` installed it at
  `.claude/agents/code-analyst.md`, otherwise the plugin-namespaced
  `hfx:helpers:code-analyst`.
- For external library/API docs you are unsure about, use `WebFetch` /
  `WebSearch` / Context7 MCP yourself — do not delegate.
- **Push back on over-engineering.** If the user's proposed approach
  is materially more complex than a reasonable alternative (e.g.,
  adopting a library when 20 lines of code would do, introducing a
  new state-management layer for one component, building a config
  system for one flag), surface the simpler option as a Tier-2
  question with the simpler path marked `(Recommended)` — do not
  silently implement the more complex path just because the user
  named it first. The user can still pick the complex path, but they
  must do so with the simpler path on the table.

---

## 3. The [a]/[e]/[q]/[r] gates

After grilling reaches "sync" (user and you agree on intent), present:

```
[a] approve — write plan.md + plan.<worker>.md files
[e] edit    — keep grilling, refine sync
[q] question — user asks something
[r] reject  — discard, move ticket to trash/, suggest /compact and restart
```

After plan files are written, present again:

```
[a] approve — fill approved_at + content_sha, ready for /hfx:run
[e] edit    — modify plan files inline
[q] question — user asks something
```

(No `[r]` after plan is written; use `/hfx:edit-worker` or new ticket.)

---

## 4. DoD rules (Definition of Done)

Every plan.md MUST have:
- A `## Goal` section with **one verifiable** outcome.
- A `## Verification` section with checkboxes that map 1-to-1 to the goal.
- A `## Constraints` section with an explicit `Out of scope:` list.
- **Cross-worker contract** — if `worker_count >= 2` AND the workers share
  a runtime path (HTTP request, queue message, file handoff, IPC, shared
  in-process state), `## Constraints > Technical:` MUST include a one-line
  contract that pins the wire shape and both sides' obligation. Example:
  `frontend POSTs {email: string, password: string} to /api/auth/login;
  backend re-validates password.length === 10 server-side, returns 400
  {error: "PASSWORD_LENGTH"} on mismatch`. Workers run in isolated
  worktrees and cannot see each other's decisions — without this line,
  each picks a payload shape independently and integration breaks. Omit
  for single-worker tickets and for multi-worker tickets where workers
  do not share a runtime path (e.g., backend + docupdater editing
  unrelated files).

Refuse to approve a plan that has any of:
- Vague goals ("improve performance", "clean up").
- Verification items that say "manual review" or "looks good".
- Empty `Out of scope:` (every plan has some).

### No-placeholders deny-list (applies to every `plan.<worker>.md ## Tasks`)

Refuse to approve a worker plan whose tasks contain any of the
following — these are plan failures, not minor cleanups:

- `TBD`, `TODO`, `FIXME` as a task line.
- `implement later`, `come back to this`, `will add in a follow-up`.
- `add appropriate error handling` without specifying which error path.
- `similar to Task N` (every task must stand on its own).
- `write tests for the above` without naming the cases.
- A task that has no observable change in the diff (e.g. "think about X").
- A task whose effort is unknown ("might be small, might be large").
- A task that bundles >5 file edits with no sub-tasks (split it).

Why: the spec-reviewer compares the diff against these tasks one by
one. Placeholders create ambiguous PASS/FAIL — reviewer can't decide if
the task was met. The fix is to either make the task concrete or to
split it into smaller, concrete tasks.

---

## 4a. Review-mode and security-review proposal (Step 6.5 in /hfx:plan)

After plan files are written but before the plan gate, scan the draft
for risk signals and propose `review_mode` and `security_review` to
the user **in a single AskUserQuestion call**. If no signals fire,
keep both at `off` and skip the question — speed-first.

### Risk signal detection

Compute these booleans by inspecting the plan files. Scan BOTH:
(a) paths in `## Files manifest` and `## Reference files`, and
(b) the natural-language text of `## Goal` and `## Tasks` (since a new
ticket may describe risky work before the planner knows the exact path).

| Signal | Path match | Natural-language keyword match |
|--------|-----------|--------------------------------|
| `worker_count` ≥ 2 | (not applicable) | (not applicable) |
| `touches_auth` | `auth*`, `login*`, `session*`, `token*`, `jwt*`, `oauth*`, `password*`, `permission*`, `role*` | `auth`, `login`, `session`, `token`, `jwt`, `oauth`, `password`, `permission`, `role`, `sign-in`, `sso` |
| `touches_secrets` | `.env*`, `secrets*`, `*.pem`, `credentials*`, `config/auth*` | `secret`, `credential`, `api key`, `apikey`, `private key` |
| `touches_ci` | `.github/workflows/*`, `.gitlab-ci*`, `Dockerfile*`, `buildspec*`, `Jenkinsfile` | `workflow`, `pipeline`, `dockerfile`, `ci/cd`, `github action` |
| `touches_prompts` | `agents/**/*.md`, `.claude/agents/**`, `skills/**/SKILL.md`, `templates/*.md` | `prompt`, `agent`, `subagent`, `system prompt`, `worker` |
| `touches_public_api` | (not applicable) | `endpoint`, `route`, `public api`, `exported`, `breaking change`, `migration` |

A signal fires if EITHER the path-match OR the keyword-match hits.

### Recommended values

**review_mode:**
- `strict` if: `worker_count >= 2` OR `touches_auth` OR `touches_public_api`
- `lenient` if: single worker with 2–5 tasks (not covered above)
- `off` if: single worker with 1 task AND only touches docs/comments/dep bumps

**security_review:**
- `full` if: brand-new auth/oauth system, external API integration with credentials, large dependency bump (≥5 new direct deps)
- `diff` if: `touches_auth` OR `touches_secrets` OR `touches_ci` OR `touches_prompts`
- `off` otherwise

### Question shape

If recommended values are both `off`, **skip the question** entirely.
Otherwise, ask ONE consolidated question (see `/hfx:plan` Step 6.5
for the AskUserQuestion options block):

> ⚠️ This plan touches **<reason>**. Suggested:
> - review_mode = `<X>`
> - security_review = `<Y>`
>
> [a] approve recommendation
> [s] strict + diff (both maxed)
> [n] keep both off (speed-only)
> [e] customize each axis

Record the chosen values into `plan.md` frontmatter BEFORE Step 7's
sha computation, so the gate locks them in.

### Why an opt-in question

hfx is speed-first (README §"Why this exists"). Reviewer dispatches
cost extra LLM calls and minutes. Default-off means the 80–90% of
tickets that touch no risky surface stay fast; only the tickets
with actual risk signals trigger this question.

---

## 5. Memory protocol (read + write)

### Read side — active memory retrieval at /hfx:plan Step 1

`/hfx:plan` Step 1 reads `.harness/memory/INDEX.md`. After that, do not
stop at the one-line hooks — **load the top 1–3 theme bodies** whose
INDEX line shares ≥1 lowercase keyword with `$ARGUMENTS`. This is
deterministic keyword match, not LLM judgment. Pseudocode:

```
STOP_WORDS = {a, an, and, the, to, of, in, on, for, with, fix, add,
              update, change, make, do, use, new, also, please}
keywords = lowercase($ARGUMENTS).split() - STOP_WORDS
matches  = []
for line in INDEX.md:
  hook = lowercase(line)
  hits = count(k in hook for k in keywords)
  if hits >= 1:
    matches.append((hits, length(hook), line.path))
# sort: most hits first; on a tie, shorter hook wins
# (a shorter index line is usually a narrower, more specific theme).
top_3 = matches.sort_by(hits desc, length asc).take(3)
for path in top_3:
  Read(`.harness/memory/<path>`)
```

If keywords list is empty after stop-word removal, OR 0 matches → skip;
memory adds no value here. The point is to surface prior learnings
*during grilling*, so the planner doesn't ask the user to repeat
decisions already recorded.

Loaded memory must visibly affect grilling — quote the relevant line
back to the user when it changes a question or assumption. Silent reads
are wasted reads.

### Write side — propose learnings after /hfx:run succeeds

After `/hfx:run` completes successfully and user accepts results:

1. Read `.harness/memory/INDEX.md`.
2. Propose 0–3 candidate learnings to add. A learning is worth saving
   only if ALL three gates pass:
   - **Saves future time** — it would have saved time on this very
     ticket if known beforehand.
   - **Non-obvious from code** — it would not be found by a `grep` over
     the project files.
   - **Permanent, not a workaround** — the fix this learning describes
     is a permanent solution, not a temporary workaround for a bug. If
     the learning is "we did X to work around bug Y," the right move is
     to file a bug ticket — do NOT save it as memory. Workarounds
     become stale the moment the underlying bug is fixed, at which
     point the learning lies to future readers.
3. Each saved learning MUST follow the structure below — both the
   YAML frontmatter and the 5-line body skeleton are required:

   ```markdown
   ---
   files:
     - <repo-relative path the learning relates to>
     - <another path, if applicable>
   ---

   Problem: <one line — what situation does this apply to>
   Cause:   <one line — why it happens>
   Fix:     <one line — what to do, concretely>
   Why:     <one line — why this fix is correct, not just convenient>
   When-not-to-apply: <one line — the condition under which this
                       learning becomes obsolete>
   ```

   Rules for the structure:
   - Body is **≤10 lines total** after the frontmatter. Long
     explanations belong in the commit message or an external doc;
     the learning itself stays compact.
   - `files:` is a flat YAML list of repo-relative paths. If the
     learning is not file-specific (e.g., a project-wide convention),
     use `files: []`. Future tooling globs these to detect stale
     learnings whose referenced files no longer exist.
   - `When-not-to-apply:` is the single most important line — the
     learning declares its own expiry condition. Examples:
     `When-not-to-apply: when X library is upgraded past v3`,
     `When-not-to-apply: when the auth refactor in ticket Z lands`,
     `When-not-to-apply: never — this is a permanent project convention`.
     If you cannot articulate when the learning becomes obsolete, the
     learning is probably too vague to save.
4. For each candidate, show:
   - Proposed file (existing theme or new).
   - One-line summary that will appear in INDEX.md.
   - The full frontmatter + 5-line body as it will be written.
5. **Overlap check (deterministic):** grep each candidate's
   title-keywords against existing `<theme>.md` files. If any file
   matches, present the user with `[s]upersede / [a]ppend / [n]ew / [skip]`
   instead of plain `[y]/[n]`. Never auto-pick `supersede`.
6. Ask `[y]es / [n]o` (or the overlap variant) per candidate. Only
   write what the user confirms.

**Never** save:
- Code patterns already visible in the repo.
- Git history facts.
- One-off fix recipes ("we removed line X to fix Y") — those live in the commit message.
- Workarounds — file a bug ticket instead (see gate 3 above).

---

## 6. Anti-patterns to avoid (from principle.md)

- **Self-evaluation bias**: The planner does not also verify its own dispatched
  workers as PASS. Validation comes from a separate fresh Agent or explicit
  user accept.
- **Kitchen sink**: One ticket = one goal. If grilling reveals a second goal,
  ask the user to split into two tickets.
- **Mega-session**: Tickets must be sprint-sized. If a plan exceeds ~5 worker
  steps, ask the user whether to split.
- **Unbounded exploration**: Set search boundaries (refs.yaml `conditional`
  keywords) before reading. Do not free-roam the repo.

---

## 7. How to use refs.yaml

- `always:` — Read every time `/hfx:plan` starts (small, hot context).
- `conditional:` — Read only when user request mentions matching keywords.
- `manual:` — Listed for reference; the user names them in `/hfx:plan`
  arguments to force-include.

Add new entries when you find a doc that should have been auto-loaded.
Propose this edit at the end of the ticket, in the memory update step.

---

## 8. Language

- **Conversation language** — mirror the user's most recent message.
  This applies to **every chat reply**, including replies to questions
  **about** an artifact (`plan.md`, a worker file, a generated report).
  The artifact itself stays in the artifact language; the discussion
  about it follows the user.
- **Artifact language: `<LANG>`** — write natural-language sections
  inside `plan.md`, `plan.<worker>.md`, and worker / reviewer report
  files in `<LANG>`. Section headers, frontmatter keys, status enums,
  shell commands, file paths, and code identifiers stay English.
- At `/hfx:plan` Step 4, add this line to `plan.md ## Constraints >
  Technical:` so workers (which don't see this file) obey it too:
  `Artifact language: <LANG> (natural-language sections only)`.

## 9. External skills named by the user

**Trigger.** This rule applies when the user requests a non-hfx skill
be invoked **for this ticket**, via any of these channels:
(a) free chat turn, (b) `AskUserQuestion` answer (including
Other / free-text), (c) `/hfx:plan` arguments. A non-hfx skill is one
whose name does not match `hfx:*` and is not bundled under
`${CLAUDE_PLUGIN_ROOT}/skills/`. Incidental mentions (skill named as
comparison, retrospective, or aside — not as a request to invoke it
now) do NOT trigger this rule.

**Two choices.** You may:

- **Call the skill** as part of `/hfx:plan` (typical for design /
  ideation skills whose output you can transcribe into `plan.md`).
- **Decline to call it**, when the skill's premise conflicts with the
  ticket (e.g. user provided a pixel-locked screenshot and the skill
  is about creative invention).

**If you decline, you MUST:**

1. In the same assistant turn, BEFORE any `AskUserQuestion` call,
   state the reason in chat. Example: `Declined /frontend-design
   because the attached screenshot pins color and layout; the skill's
   bold-aesthetic premise would generate spec violations.`
2. Write the carrier file `<TICKET_DIR>/declined-skills.json` as a
   JSON array (one entry per declined skill) immediately after
   approval. Schema:
   ```json
   [{
     "name": "/frontend-design",
     "reason": "<one-sentence rationale>",
     "channel": "chat | askuserquestion-other | args",
     "declared_at": "<ISO timestamp>"
   }]
   ```
   `/hfx:run` Step 5 reads this file and emits one
   `[skill-declined]` entry per item into
   `results.md ## Open questions`.
3. Reframing `[a]/[e]/[q]/[r]` so "approve without the named skill"
   appears as Recommended is allowed only after step 1 above. The
   user must see the reason before the option list.
