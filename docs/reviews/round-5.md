# Critical review — round 5 (native loader run)

**Reviewer:** native `claude --plugin-dir` session run by the user.
**Mandate:** test plugin loader + SKILL execution end-to-end natively.
**Verdict:** 1 design-level bug surfaced and fixed.

This is the first round to exercise the **actual Claude Code plugin
loader**. Rounds 1-3 were static, round 4 was a simulation in the
plugin-repo session. Native execution surfaced what neither approach
could.

---

## CRIT-RUNTIME-2 — `<ticket-id>` placeholder inside ` ```! ` shell blocks

**Symptom (user-reported native session):**
```
/plan i want to add endpoint
Error: Shell command failed for pattern "!       bash
  "/Users/yu_s/Documents/GitHub/hfx/scripts/compute-sha.sh"
  "/Users/yu_s/Documents/GitHub/5-13-hfx-test/.harness/tickets/active/<ticket-id>"":
  [stderr] error: plan.md not found in
  /Users/yu_s/Documents/GitHub/5-13-hfx-test/.harness/tickets/active/<ticket-id>
```

**Root cause:** Several SKILL bodies (`plan/SKILL.md`, `run/SKILL.md`)
used ` ```! ` shell-injection blocks containing the literal text
`<ticket-id>`, expecting that "the AI will substitute the real id at
execution time."

But that is not how `!` injection works. Claude Code's docs are
explicit (`/en/skills#inject-dynamic-context`): the `` `!`<command>` ``
syntax runs the command **as preprocessing, before the model sees
the skill content**. The command output replaces the placeholder.
Claude only sees the final rendered prompt. There is no opportunity
for the model to substitute a variable into a `!` block.

So when the SKILL.md was rendered, the shell tried to literally `cd`
into `.../active/<ticket-id>/` (or run `compute-sha.sh` against it),
which doesn't exist. Worse, the `mkdir` block actually **created a
directory whose name was the literal string `<ticket-id>`** — found in
the test fixture after the failed run.

**Affected sites (fixed in this commit):**

| File | Step | Original `!` block | Fix |
|---|---|---|---|
| `skills/plan/SKILL.md` | Step 6 | `mkdir -p ".harness/tickets/active/<ticket-id>"` | Replaced with `Bash` tool instruction (model substitutes id at call time) |
| `skills/plan/SKILL.md` | Step 7 [a].1 | `compute-sha.sh ".harness/tickets/active/<ticket-id>"` | Same |
| `skills/run/SKILL.md` | Step 2 | `verify-approval.sh ".harness/tickets/active/<ticket-id>"` | Same |
| `skills/run/SKILL.md` | Step 6 [a] | `move-ticket.sh .harness "<ticket-id>" done` | Same |

**Unaffected `!` blocks (kept as-is — they use only env vars, no dynamic placeholders):**

| File | Step | Block |
|---|---|---|
| `skills/init/SKILL.md` | Pre-flight | `ls "${CLAUDE_PROJECT_DIR}/.harness"` |
| `skills/plan/SKILL.md` | Step 0 | `ls "${CLAUDE_PROJECT_DIR}/.harness/planner-policy.md"` |
| `skills/plan/SKILL.md` | Step 2 | `ls "${CLAUDE_PROJECT_DIR}/.claude/agents/"` |
| `skills/run/SKILL.md` | Step 1 | `ls -1t "${CLAUDE_PROJECT_DIR}/.harness/tickets/active"` |
| `skills/run/SKILL.md` | Step 2b | `ls "${CLAUDE_PROJECT_DIR}/.claude/agents/"` |
| `skills/status/SKILL.md` | (status) | `ls .../tickets/active` (small) |
| `skills/edit-worker/SKILL.md` | Step 1 | `ls "${CLAUDE_PROJECT_DIR}/.claude/agents/"` |

All retained `!` blocks: ENV-var only, no `<dynamic-placeholder>`. They
benefit from preprocess-time injection (cheap, deterministic, cache-warm).

## How the fix works

The replaced blocks now read like this:

```
Use the `Bash` tool (do NOT use a ` ```! ` injection block — the
ticket-id is dynamic) to compute the sha, substituting the actual
ticket-id you generated in Step 6:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/compute-sha.sh" \
         "${CLAUDE_PROJECT_DIR}/.harness/tickets/active/<actual-ticket-id-here>"
```

When the model reads this, it issues a `Bash` tool call at execution
time. The model has the actual ticket-id in its context (just generated
or just picked from `ls`), so the substitution happens correctly. The
trade-off is one extra tool round-trip vs. preprocess injection — not
hot path, fine for these gate steps.

## Why prior rounds missed it

- Rounds 1-3 (static analysis): never ran the `!` injection. Treated
  `<ticket-id>` as legible prose for the model, missed that `!` is
  preprocess.
- Round 4 (simulation in the plugin-repo session): simulated the SKILL
  body by hand using `Bash` directly — bypassed the `!` injection path
  entirely, so the buggy code path was never exercised.

Round 5 is the first to actually run `--plugin-dir` natively. The bug
appeared at the first `/hfx:plan` call.

## What's still untested natively

The user reported the bug at `/hfx:plan`'s pre-Step-6 stage. We don't
yet know whether:
- Step 1 `Read planner-policy + refs + memory INDEX` works natively.
- Step 4 grilling loop with `AskUserQuestion` flows correctly.
- Step 6 file generation produces the right `dispatch_graph` YAML.
- Step 7 [a] gate fires `compute-sha.sh` correctly **after the fix**.
- `/hfx:run` Step 2 verify gates correctly **after the fix**.
- Worker dispatch via `subagent_type="backend"` resolves to
  `.claude/agents/backend.md` (the open question from round 4).

A native re-run with the cleaned fixture is the next step.

## Other observations from the user's native session

- The user's `.claude/agents/` had a `code-checker.md` file we didn't
  ship. The user likely added it manually or asked planner to create
  it. Either way, it's user-owned, not a plugin defect. Not touched.
- The literal `<ticket-id>` directory was found in
  `.harness/tickets/active/<ticket-id>/`. This is evidence the `!`
  injection ran `mkdir -p` with the unsubstituted string. Cleaned up
  manually as part of the fixture reset.

Round 5 verdict: 1 design-level critical fixed. Native re-run needed.
