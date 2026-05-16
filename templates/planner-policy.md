# Planner policy

This file is loaded by `/hfx:plan` at the start of every planning session.
Edit it freely to customize how the planner thinks about your project.

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

Refuse to approve a plan that has any of:
- Vague goals ("improve performance", "clean up").
- Verification items that say "manual review" or "looks good".
- Empty `Out of scope:` (every plan has some).

---

## 5. Memory update protocol

After `/hfx:run` completes successfully and user accepts results:

1. Read `.harness/memory/INDEX.md`.
2. Propose 0–3 candidate learnings to add. A learning is worth saving only if:
   - It would have saved time **on this very ticket** if known beforehand, AND
   - It is non-obvious from the code alone (i.e., would not be found by grep).
3. For each candidate, show:
   - Proposed file (existing theme or new).
   - One-line summary that will appear in INDEX.md.
   - The full memory body (≤10 lines).
4. Ask `[y]es / [n]o` per candidate. Only write what the user confirms.

**Never** save:
- Code patterns already visible in the repo.
- Git history facts.
- One-off fix recipes ("we removed line X to fix Y") — those live in the commit message.

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
