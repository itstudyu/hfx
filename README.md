# hfx — planner-led harness for Claude Code

> A Claude Code plugin where the **main session is the planner**. It grills
> you, drafts a plan, then dispatches workers in fresh sub-agent contexts —
> so heavy implementation work never pollutes your planning context.

```
                 user
                  │
                  ▼
       /hfx:plan ──── (main = planner) ──── /hfx:run
                  │                              │
                  │  (grill, draft, gate)        │  (verify gate, dispatch)
                  ▼                              ▼
       .harness/tickets/active/             ┌──Agent──┐
         <id>/plan.md                       │ backend │  fresh context
         <id>/plan.backend.md               ├─────────┤  isolation: worktree
         <id>/plan.frontend.md              │frontend │  fresh context
         <id>/plan.docupdater.md            ├─────────┤
                                            │docupdt. │  fresh context
                                            └─────────┘
                                              ↓
                                            results.md
                                              ↓
                                       [a]ccept → done/
                                              ↓
                                       memory update?
```

---

## Why this exists

- **Speed / efficiency / performance** first. No external services, no
  long-running daemons. Workers are in-process `Agent` calls; independent
  ones run in parallel within a single turn.
- **Context isolation.** The planner stays small. Workers see only their
  per-worker plan + the parent plan. Code analysis is delegated to a
  read-only helper that returns summaries.
- **Hard approval gate.** `plan.md` carries `approved_at` and
  `content_sha`; `/hfx:run` recomputes the sha and aborts if anything
  drifted after approval.
- **No self-evaluation.** Workers don't grade themselves. The planner
  doesn't grade workers. The user accepts; a separate fresh Agent reviews
  the plugin itself.

---

## Install

Inside Claude Code, add the marketplace and install the plugin. Use the
full HTTPS URL — the short `owner/repo` form makes Claude Code try
`git@github.com:...` over SSH, which fails unless you have SSH keys
configured for GitHub.

```
/plugin marketplace add https://github.com/itstudyu/hfx
```

```
/plugin install hfx@hfx-marketplace
```

### Verify

```
/plugin
```

You should see `hfx` listed with its version. `/help` will show the
five `/hfx:*` slash commands (`init`, `plan`, `run`, `status`,
`edit-worker`).

### Update later

```
/plugin marketplace update hfx-marketplace
/plugin update hfx@hfx-marketplace
```

---

## Quick start

```text
# 1. From your project root, in Claude Code:
/hfx:init

#    (Pick which default workers to install: backend / frontend / docupdater.
#     Pick whether to install the code-analyst helper.
#     Per worker, pick model + reference docs.)

# 2. Plan a ticket:
/hfx:plan "Add a /health endpoint"

#    (The planner grills you one question at a time, drafts plan files,
#     and walks you through two approval gates.)

# 3. Run it:
/hfx:run

#    (Dispatcher verifies approval + sha, dispatches workers in parallel
#     where possible, writes results.md, and asks you to [a]ccept.)
```

---

## Commands

| Command           | Purpose                                              | User-invoked only |
|-------------------|------------------------------------------------------|------------------|
| `/hfx:init`       | Bootstrap `.harness/` in the current project          | yes |
| `/hfx:plan "<r>"` | Grill + draft + gate a ticket                        | yes |
| `/hfx:run [<id>]` | Verify gate and dispatch workers for an approved ticket | yes |
| `/hfx:status`     | List active tickets and next actions                  | yes |
| `/hfx:edit-worker "<r>"` | Edit an installed worker (model/tools/desc/body) | yes |
| `/hfx:security`   | Standalone repo-wide security audit (CSO-style)       | yes |

All commands have `disable-model-invocation: true` — Claude will not
trigger them automatically. They run only when **you** type the slash
command.

---

## File layout

```
hfx/                                  ← plugin (installed by /plugin install)
├── .claude-plugin/plugin.json
├── skills/{init,plan,run,status,edit-worker,security}/SKILL.md
├── agents/
│   ├── workers/{backend,frontend,docupdater,
│   │            spec-reviewer,quality-reviewer,security-reviewer}.md
│   └── helpers/code-analyst.md
├── templates/{planner-policy.md, refs.yaml, memory-INDEX.md,
│              plan.md.tmpl, plan.worker.md.tmpl}
├── scripts/{compute-sha.sh, verify-approval.sh, move-ticket.sh,
│            handoff-worktree.sh}
├── docs/reviews/                      ← seven rounds of self-review records
└── README.md, CHANGELOG.md, LICENSE
```

In your **project** (created by `/hfx:init`):

```
.claude/agents/                       ← runtime workers + helpers (Claude Code's
│                                       project-level subagent location;
│                                       dispatcher reads from here)
│   ├── backend.md                    ← editable, per-project copies
│   ├── frontend.md
│   ├── docupdater.md
│   ├── code-analyst.md
│   ├── spec-reviewer.md              ← always installed; fires only
│   ├── quality-reviewer.md             when plan.md frontmatter says
│   └── security-reviewer.md            review_mode/security_review != off
.harness/
├── planner-policy.md                  ← edit freely; how the planner thinks
├── refs.yaml                          ← always-load / conditional / manual docs
├── memory/
│   ├── INDEX.md                       ← one line per learned theme
│   └── <theme>.md                     ← accumulated learnings
└── tickets/
    ├── active/<id>/plan.md, plan.<worker>.md, results.md
    ├── done/<id>/
    └── trash/<id>/
```

The plugin-shipped `agents/workers/*.md` and `agents/helpers/*.md`
under `${CLAUDE_PLUGIN_ROOT}` are **seed templates only**. `/hfx:init`
copies them into your project's `.claude/agents/`, where they become
runtime-editable.

---

## The two gates

### Sync gate (after grilling, before files are written)

```
[a] approve — write plan.md + plan.<worker>.md files
[e] edit    — keep grilling, refine sync
[q] question — ask
[r] reject  — discard, suggest /compact and restart
```

### Plan gate (after files are written, before /hfx:run can dispatch)

```
[a] approve — fill approved_at + content_sha (the hard gate)
[e] edit    — modify plan files inline (sha gets recomputed on next [a])
[q] question — ask
```

`/hfx:run` will refuse to dispatch unless **both** `approved_at` is set
**and** the recomputed sha matches what was stored at approval time. Any
edit to `plan.md` or `plan.<worker>.md` after approval invalidates the
gate and forces re-approval.

---

## Worker contract

A worker is a sub-agent file in `agents/workers/<name>.md` with frontmatter:

```yaml
---
name: backend
description: <when the planner picks this worker>
model: sonnet
tools: Read, Glob, Grep, Edit, Write, Bash
maxTurns: 30
isolation: worktree
---
```

When `/hfx:run` dispatches:

```text
Agent(
  subagent_type="backend",          # if .claude/agents/backend.md exists
  # OR  "hfx:workers:backend"       # plugin-only fallback (no /hfx:init)
  prompt = <plan.md full text> +
           <plan.backend.md full text> +
           <ticket dir absolute path>
)
```

The dispatcher resolves `subagent_type` per worker, with project-local
copies winning: bare `<name>` if `.claude/agents/<name>.md` exists
(written by `/hfx:init` and editable via `/hfx:edit-worker`), otherwise
the plugin-namespaced `hfx:workers:<name>` (or `hfx:helpers:<name>`)
shipped under `${CLAUDE_PLUGIN_ROOT}/agents/`. This means the plugin
works end-to-end even before `/hfx:init` runs — `/hfx:init` is what
unlocks per-project worker customization on top of that fallback.

The worker reads both plan files from disk (authoritative — the prompt
is a summary), implements the per-worker tasks, runs the verification
commands the plan specifies, and returns a structured summary. The
planner aggregates worker summaries into `results.md`.

Failure = fail-fast: the dispatcher does not start new levels of the
graph once any worker fails, and the ticket stays in `active/` for
inspection.

---

## Cross-worker contract (v0.0.5.8+)

When a ticket dispatches **two or more workers that share a runtime
path** (HTTP request, queue message, file handoff, IPC, shared
in-process state), the planner is required to declare a one-line
contract in `plan.md` `## Constraints > Technical:` that pins the
wire shape and both sides' obligation. For example:

```
frontend POSTs {email: string, password: string} to /api/auth/login;
backend re-validates password.length === 10 server-side, returns 400
{error: "PASSWORD_LENGTH"} on mismatch
```

Why: workers run in isolated worktrees and cannot see each other's
decisions. Without an explicit contract, frontend may POST
`{username, pw}` while backend expects `{email, password}` — both
workers pass their own checks but integration breaks. The contract
makes the wire shape part of the locked plan, so both workers agree
before any code is written.

The `spec-reviewer` (when `review_mode` is on) enforces this contract
on top of the per-task list: a producer that sends a different key, or
a consumer that skips the declared validation, is `SPEC_FAIL`
regardless of whether all tasks are MET.

Single-worker tickets and multi-worker tickets where workers don't
share a runtime path (e.g., `backend` + `docupdater` editing unrelated
files) are exempt.

---

## Reviewer workers (v0.0.5+)

Three read-only reviewer workers (`spec-reviewer`, `quality-reviewer`,
`security-reviewer`) ship by default. All default to **off** — normal
tickets pay zero extra LLM cost.

- `/hfx:plan` Step 6.5 scans the draft for risk signals (auth/secrets/CI/
  prompt files, multi-worker tickets, public API). If anything fires, it
  asks once whether to enable `review_mode` (spec / spec+quality) and/or
  `security_review` (diff / full). Otherwise no question is asked.
- `/hfx:run` reads the locked frontmatter and dispatches reviewers
  automatically — no questions at run time.
- If a reviewer FAILs, the step is marked failed and the ticket stays in
  `active/`. v0.0.5 deliberately does NOT auto-retry — code never moves
  without a human signature.

`/hfx:security` is a standalone audit command for periodic use, modelled
after gstack `/cso`. It applies the same zero-noise discipline (8/10
confidence gate, concrete exploit scenario required, anti-manipulation,
codified false-positive precedents). **Scope is intentionally narrower
than gstack `/cso`**: hfx covers the web-app hot path (secrets, deps,
CI, prompt/skill supply chain, auth, OWASP-lite). For deep infra / LLM
/ STRIDE / data-classification audits, use gstack `/cso` directly.

## Helpers

`code-analyst` (read-only, model: haiku): called by the planner during
`/hfx:plan` grilling to answer a single specific question about a
codebase without dragging file contents into the main context. Returns
a structured summary with `file:line` citations. Has `disallowedTools:
Edit, Write` — cannot modify anything.

---

## Memory

After `/hfx:run` succeeds and the user accepts, the planner proposes
0–3 learnings to save. A learning is worth saving only if:

- It would have saved time **on this very ticket** if known beforehand.
- It is non-obvious from the code alone (not findable by grep).

Saved entries land in `.harness/memory/<theme>.md` and are indexed by a
one-line entry in `.harness/memory/INDEX.md` (which the planner reads at
the start of every `/hfx:plan` session).

---

## Principles (the things this plugin will not do)

From `/Users/yu_s/.claude/reference/hfx/principle.md`:

1. **Think before coding** — assumptions are written down (in plan.md).
2. **Simplicity first** — two-adapters rule: no abstraction without two
   concrete call sites.
3. **Surgical changes** — every edited line traces back to a Task in a
   `plan.<worker>.md`.
4. **Goal-driven execution** — DoD before start, no "looks good".
5. **Context isolation** — main planner small, workers fresh, code-analyst
   read-only.
6. **Anti-patterns** — no self-evaluation, no kitchen-sink tickets, no
   mega-sessions, no unbounded exploration.

---

## Testing the plugin

The plugin was developed end-to-end against a fixture project (a
trivial Node HTTP server) using a scripted scenario. The development
scenario, its results, and the seven rounds of critical self-review
(`docs/reviews/round-1..7.md`) document what was exercised and which
bugs each round caught.

To smoke-test the plugin yourself in a throwaway directory:

```bash
mkdir /tmp/hfx-smoke && cd /tmp/hfx-smoke
git init -q && echo '{}' > package.json && git add . \
  && git -c user.email=t@x -c user.name=t commit -q -m init
claude --plugin-dir /path/to/hfx
# inside Claude Code:
#   /hfx:init
#   /hfx:plan "Add a /health endpoint returning {status:ok} as JSON"
#   /hfx:run
#   /hfx:status
```

---

## Versioning

The current release is the initial planner-led harness, hardened by
seven rounds of self-review. No backwards compatibility
to any earlier `hfx` (the repo was reset). Worker file format may evolve
in `v0.x` minor versions; the plan file `frontmatter` schema is intended
to be stable.

Per-version changes: see [CHANGELOG.md](./CHANGELOG.md).

## License

MIT. See `LICENSE`.
