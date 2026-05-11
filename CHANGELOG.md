# Changelog

All notable changes to `claude-code-goal` are documented here. The format
is based on [Keep a Changelog](https://keepachangelog.com/) and this
project adheres to [Semantic Versioning](https://semver.org/) patch bumps
on every commit and minor/major bumps when explicitly triggered.

## [0.1.0] - 2026-05-11

Initial public release as a Claude Code plugin.

### Added

- Persistent `/goal` command: set a long-running objective and Claude
  auto-continues across turns via a `Stop` hook until the goal is paused,
  cleared, or completed.
- Codex-verbatim continuation and `budget_limited` prompts with
  XML-escaped `<untrusted_objective>` delimiters so a hostile objective
  cannot break out.
- Adversarial completion audit: `/goal complete` gates on a separate
  `claude -p` subprocess with a hostile prompt, write tools disabled,
  and a narrowed Bash allowlist.
  Outcome is `pass` (→ complete), `fail` (→ active with missing items
  injected into the next continuation), or `error` (→ stays
  `pending_audit`, retry with `/goal complete` or override with
  approved `/goal complete --force`).
- Three audit modes: `adversarial` (default), `self` (codex-style worker
  self-audit), `off` (legacy alias for `CLAUDE_GOAL_AUDIT_DISABLE=1`).
  Configurable via `~/.claude/plugins/data/claude-code-goal-balakumar/config.toml`
  or `/goal config set audit.mode <value>` or env vars. Weaker modes and
  `--force` require launch-time `CLAUDE_GOAL_FORCE_OK=1` approval.
- Soft token budgets with `K` / `M` / `B` / `T` suffix parsing.
  Auto-transition to `budget_limited` when `tokens_used >= token_budget`.
- `SessionStart` hook propagates `CLAUDE_SESSION_ID` so parallel Claude
  Code sessions stay isolated even when `TERM_SESSION_ID` is unreliable
  (tmux, ssh, VS Code terminals).
- Stop-hook early-out via a marker file so sessions without any active
  goal pay one `stat()` syscall per turn instead of a SQLite open.
- Events table with composite index on `(goal_id, event, created_at)` and
  30-day GC on clear / complete to keep the runaway-guard query fast
  under heavy parallel use.

### Plugin packaging

- Distributed as a Claude Code plugin at
  `balakumardev/claude-code-goal`, listed in the `balakumar`
  marketplace at `balakumardev/claude`.
- Install: `/plugin marketplace add balakumardev/claude` then
  `/plugin install claude-code-goal@balakumar`.
- State persists at `$CLAUDE_PLUGIN_DATA` (i.e.
  `~/.claude/plugins/data/claude-code-goal-balakumar/`).

[0.1.0]: https://github.com/balakumardev/claude-code-goal/releases/tag/v0.1.0
