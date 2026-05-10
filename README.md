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

## Notes

Claude Code custom skills do not currently expose reliable live per-turn token usage to markdown commands, so budgets are soft — use `add-tokens` to account manually (or drive it from a hook). Elapsed-time tracking is local and persistent.

The Stop hook blocks Claude from stopping while the current goal is active. It stops blocking when you run `/goal pause`, `/goal clear`, or `/goal complete`.

By default, the runaway guard allows up to 500 Stop-hook continuations for a single active goal. That high default is intentional: `/goal` is meant for long-running work where Claude may need many turns to finish. If you want a stricter cap, set `CLAUDE_GOAL_MAX_STOP_CONTINUES` before launching Claude Code:

```bash
export CLAUDE_GOAL_MAX_STOP_CONTINUES=50
```

See `goal/references/codex-goal-research.md` for the full parity report, including the four Codex features that cannot be ported (model-visible tools, queued slash commands, Plan-mode gating, and thread-resume restoration).

## Test

```bash
python3 -m pytest tests
```
