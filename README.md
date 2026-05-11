# claude-code-goal

A Codex-style `/goal` command for Claude Code.

It gives Claude Code a persistent local goal state, Codex-verbatim continuation and budget-limit prompts, XML-escaped objective delimiters, pause/resume/clear/complete controls, completion-audit guardrails, token accounting with auto `budget_limited` promotion, and a Stop hook that keeps Claude working while a goal is active.

## Install

```bash
git clone https://github.com/balakumardev/claude-code-goal.git
cd claude-code-goal
./install.sh
```

This installs:

- `~/.claude/skills/goal` as a symlink to this repo's `goal/` directory
- a user-level Claude Code `Stop` hook in `~/.claude/settings.json`
- a user-level Claude Code `SessionStart` hook that exports `CLAUDE_SESSION_ID` into each session's Bash env, so parallel Claude Code sessions stay isolated even when `TERM_SESSION_ID` isn't reliable (tmux, ssh, VS Code terminals).

The `goal/` directory is the Claude skill package. It contains `SKILL.md`, `scripts/claude_goal.py`, and reference notes.

State is stored at:

```text
~/.claude/goal/goals.sqlite
```

## Usage

```text
/goal find and fix the flaky auth tests
/goal --tokens 250K do deep research and build the full prototype
/goal
/goal status
/goal pause
/goal resume
/goal clear
/goal complete
```

Token budgets accept `K`, `M`, `B`, and `T` suffixes.

When a goal is active, `/goal` returns the Codex-verbatim continuation prompt: objective wrapped in `<untrusted_objective>` (XML-escaped), a budget block with raw integer tokens/time/remaining, and the full seven-bullet completion audit plus anti-proxy rules.

If `tokens_used` crosses `token_budget`, the goal auto-transitions to `budget_limited` and the helper returns the budget-limit prompt instead (wrap up, summarize, leave a clear next step). You can feed token usage in via:

```bash
python3 ~/.claude/skills/goal/scripts/claude_goal.py add-tokens <N>
```

## Completion audit

Runs by default on every `/goal complete`. You can switch to `self` mode (codex-default: worker marks itself complete) or `off` mode via `/goal config set audit.mode <value>`.

`/goal complete` does not mark the goal done on its own. Instead it moves the goal to `pending_audit` and spawns an **adversarial audit** in a separate `claude -p` process with a hostile system prompt ("prove the worker wrong"), read-only tools (no Edit / Write), no shared session, and no access to the worker's reasoning. The auditor can only see the objective text and the repository on disk.

Three outcomes:

| Auditor says | Result |
|---|---|
| `pass` | Goal transitions to `complete`; budget report fires. |
| `fail` | Goal reverts to `active`; the auditor's `missing` list is injected into the next continuation prompt so Claude has to address every item before re-running `/goal complete`. |
| `error` (API down, timeout, malformed JSON) | Goal stays at `pending_audit`; re-running `/goal complete` retries the audit. |

Override the audit (when you're sure the auditor is wrong, or when running offline):

```bash
# --force requires the user to have set CLAUDE_GOAL_FORCE_OK=1 when launching
# Claude Code. This is the guardrail against a drifting worker bypassing the
# audit on its own: the skill's Bash tool calls don't inherit this variable,
# so only YOU (the user) can set it.
export CLAUDE_GOAL_FORCE_OK=1   # in the shell where you run `claude`
/goal complete --force          # one-shot override, logs `force_complete` in events

# Alternative: disable the auditor entirely for this session
CLAUDE_GOAL_AUDIT_DISABLE=1
```

Tune the auditor via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_GOAL_AUDIT_MODEL` | `sonnet` | Model id passed to `claude -p --model`. |
| `CLAUDE_GOAL_AUDIT_TIMEOUT` | `180` | Seconds before the auditor is killed and treated as `error`. |
| `CLAUDE_GOAL_AUDIT_DISABLE` | unset | `1` skips the auditor entirely (legacy alias for `audit.mode = off`). |

## Configuration

Persistent configuration lives at `~/.claude/goal/config.toml` (override the directory with `CLAUDE_GOAL_HOME`, or point at a different file with `CLAUDE_GOAL_CONFIG`). Example:

```toml
[audit]
mode = "adversarial"
model = "sonnet"
timeout = 180
```

### Audit modes

- `adversarial` (default) — spawns `claude -p` as a separate session to verify the objective was met. Hostile system prompt, read-only tools, independent session. `/goal complete --force` still requires `CLAUDE_GOAL_FORCE_OK=1` in the shell that launched Claude Code.
- `self` — skips the subprocess and trusts the worker's own completion claim. This is the pre-audit codex-default behavior (the worker marks itself complete after the seven-bullet audit). Logs a `self_audit` event. `--force` is a no-op here because there is nothing to force past.
- `off` — no audit at all. Legacy alias for `CLAUDE_GOAL_AUDIT_DISABLE=1`. Logs `force_complete`.

### Env-var overrides

Env vars take precedence over the config file for the current session.

| Variable | Config key | Default | Purpose |
|---|---|---|---|
| `CLAUDE_GOAL_AUDIT_MODE` | `audit.mode` | `adversarial` | One of `adversarial`, `self`, `off`. |
| `CLAUDE_GOAL_AUDIT_MODEL` | `audit.model` | `sonnet` | Model id passed to `claude -p --model`. |
| `CLAUDE_GOAL_AUDIT_TIMEOUT` | `audit.timeout` | `180` | Seconds before the auditor is killed and treated as `error`. |
| `CLAUDE_GOAL_AUDIT_DISABLE` | — | unset | `1` is a legacy alias for `audit.mode = off`. |

### `/goal config` subcommand

Inspect and edit the config file without hand-editing TOML:

```text
/goal config list
/goal config get audit.mode
/goal config set audit.mode self
```

## Notes

Claude Code custom skills do not currently expose reliable live per-turn token usage to markdown commands, so budgets are soft — use `add-tokens` to account manually (or drive it from a hook). Elapsed-time tracking is local and persistent.

The Stop hook blocks Claude from stopping while the current goal is `active` or `pending_audit`. It stops blocking when you run `/goal pause`, `/goal clear`, or `/goal complete` (with a passing audit or `--force`).

### Parallel sessions

The skill is designed to work across many concurrent Claude Code sessions:

- Each session is keyed by its real Claude Code session id (`CLAUDE_SESSION_ID`) via the `SessionStart` hook, so two sessions in the same repo / terminal tab never collide.
- The Stop hook stats a marker file at `~/.claude/goal/.active` before touching SQLite — sessions without any active goal pay one syscall per turn, not a DB open.
- The `events` table carries a composite index on `(goal_id, event, created_at)` so the runaway-guard query stays fast under heavy use. Events older than 30 days are GC'd on every `/goal clear` and successful `/goal complete`.

By default, the runaway guard allows up to 500 Stop-hook continuations for a single active goal. That high default is intentional: `/goal` is meant for long-running work where Claude may need many turns to finish. If you want a stricter cap, set `CLAUDE_GOAL_MAX_STOP_CONTINUES` before launching Claude Code:

```bash
export CLAUDE_GOAL_MAX_STOP_CONTINUES=50
```

See `goal/references/codex-goal-research.md` for the full parity report, including the four Codex features that cannot be ported (model-visible tools, queued slash commands, Plan-mode gating, and thread-resume restoration).

## Test

```bash
python3 -m pytest tests
```
