# Codex /goal Research Notes

Research date: 2026-05-10.

Local Codex version: `@openai/codex` 0.128.0, `codex-cli 0.128.0`.

Relevant files inspected from the Codex reference implementation:

- `codex-rs/features/src/lib.rs`: feature flag `Goals` — "persisted thread goals and automatic goal continuation."
- `codex-rs/state/migrations/0029_thread_goals.sql`: `thread_goals` schema.
- `codex-rs/state/src/runtime/goals.rs`: SQLite persistence, replace/insert/update/delete, wall-clock and token accounting, budget limiting.
- `codex-rs/core/src/goals.rs`: `Session` glue, continuation orchestration, budget-limit injection, XML-escape helper.
- `codex-rs/core/src/tools/handlers/goal_spec.rs`, `goal.rs`, `goal/{get_goal,create_goal,update_goal}.rs`: model-visible tools `get_goal`, `create_goal`, `update_goal`.
- `codex-rs/core/templates/goals/continuation.md`: continuation prompt and completion-audit requirement.
- `codex-rs/core/templates/goals/budget_limit.md`: budget-limit prompt.
- `codex-rs/tui/src/goal_display.rs`: elapsed formatter, status labels, usage summary.
- `codex-rs/tui/src/status/helpers.rs`: `format_tokens_compact`.
- `codex-rs/tui/src/app/thread_goal_actions.rs`: TUI slash-command actions.
- `codex-rs/tui/src/chatwidget/{slash_dispatch.rs,goal_menu.rs,goal_validation.rs,goal_status.rs}`: command dispatch, menus, objective validation.
- `codex-rs/tui/src/chatwidget/tests/slash_commands.rs`: `/goal`, `/goal pause`, `/goal resume`, `/goal clear`, queued-command behavior.
- `codex-rs/protocol/src/protocol.rs`: `MAX_THREAD_GOAL_OBJECTIVE_CHARS = 4000`.

## Behavior cloned in this skill

- Persistent local SQLite state (one goal per session).
- Status enum `active`, `paused`, `budget_limited`, `complete` with identical CHECK constraint and terminal-state stickiness:
  - `budget_limited → paused` is a no-op.
  - `paused/active → active` on an exhausted budget stays `budget_limited`.
  - `paused/active → budget_limited` fires automatically when `tokens_used >= token_budget`.
- Objective validation: 4000 code-point limit, empty rejection, identical error strings and the `Put longer instructions in a file…` remediation hint.
- Soft token-budget parsing with `K`, `M`, `B`, `T` suffixes; rejects ≤ 0.
- Codex elapsed formatting (`59s`, `1m`, `1h 30m`, `2d 23h 42m`, …).
- Codex compact-token formatting (`1.23K`, `12.5K`, `50K`, `500K`, `1M`, `1.23M`, `1.5B`, `2.5T`) with sliding decimals and trailing-zero trimming; negatives clamp to 0.
- Humanized status labels (`limited by budget` for `budget_limited`).
- Per-status `Commands:` hint in the bare `/goal` rendering.
- Bare-`/goal` usage hint when no goal is set: `Usage: /goal <objective>` + `Example: /goal improve benchmark coverage`.
- Continuation prompt is the verbatim port of `continuation.md` (objective wrapped in `<untrusted_objective>`, raw integers for time/tokens/budget/remaining, all seven audit bullets, anti-proxy paragraph, `Do not call … unless complete` rule).
- Budget-limit prompt is the verbatim port of `budget_limit.md` and is injected whenever the status is `budget_limited`.
- Completion budget report (`Goal achieved. Report final budget usage to the user: tokens used: X of Y; time used: Z seconds.`) emitted on `complete`.
- XML-escape of `&`, `<`, `>` inside `<untrusted_objective>` so a hostile objective cannot break out of the delimiter.
- Same-objective `/goal X` semantics (mirrors `codex-rs/core/src/goals.rs::set_thread_goal`):
  - Non-terminal existing goal (active / paused / budget_limited): UPDATE the row, default status to Active (reactivates a paused goal), preserve tokens_used/time_used, terminal-state stickiness still applies (a budget-exhausted goal stays budget_limited).
  - Complete existing goal: REPLACE — rotate `goal_id`, zero `tokens_used` and `time_used_seconds`.
- Distinct objective: rejected. Codex's TUI shows a replace-confirmation popup; Claude Code has no interactive popup, so the clone surfaces this as an error.
- Token accounting: the clone's `add-tokens` CLI auto-promotes to `budget_limited` from both `active` and `paused` (single mode, matching codex's `ActiveOrStopped`). Codex's default per-turn path uses `ActiveOnly` (active + budget_limited) for mid-turn accounting.

## Clone hardening beyond Codex

The clone strengthens one guarantee that Codex leaves loose: **who decides a goal is complete**.

- Codex lets the worker model call `update_goal(status="complete")` on itself — the model that did the work judges whether the work is done. The continuation prompt warns against proxy-signal completion but there is no independent verification.
- The clone gates `/goal complete` behind an adversarial audit run in a separate `claude -p` subprocess. The auditor has a hostile system prompt ("prove the worker wrong"), read-only tools (`Read`, `Glob`, `Grep`, read-only `Bash(git *)` / `cat` / `find` / `pytest`; `Edit` / `Write` / `NotebookEdit` blocked via `--disallowedTools`), no access to the worker's reasoning or tool history, and must return a structured `{"verdict":"pass"|"fail","evidence":[...],"missing":[...]}` JSON object. Passing flips the goal to `complete`; failing reverts to `active` and the missing list is injected into the next continuation prompt. Auditor errors (API down, timeout, invalid JSON) hold the goal at `pending_audit` so `/goal complete` can be retried.
- Override for false-FAIL: `/goal complete --force` (logged as `force_complete` in events) or `CLAUDE_GOAL_AUDIT_DISABLE=1` (blanket off for the session). Tunables: `CLAUDE_GOAL_AUDIT_MODEL` (default `sonnet`), `CLAUDE_GOAL_AUDIT_TIMEOUT` (default 180s).
- New status `pending_audit` (label `audit pending`) sits between `active` and `complete` during the audit window. Stop hook blocks during `pending_audit` too, so the worker session can't end while the audit is running.

## Clone extensions not present in Codex

These are additions that made sense for the Claude Code integration but do not exist in Codex:

- `--tokens` / `--token-budget` / `--budget` flags with optional `=` form and `K/M/B/T` suffix parsing. Codex sets budgets via the `create_goal` tool (integer only).
- `/goal complete` as a user-invokable command. Codex restricts status-complete to the model's `update_goal` tool. Claude Code skills cannot register custom model tools, so the clone exposes the same operation through a Bash command and also allows the user to force-complete.
- `/goal status|show|get|menu` aliases for the bare form.
- `add-tokens <N>` CLI subcommand: the clone's bridge for per-turn token accounting (Claude Code does not expose a reliable per-turn token API to skills).
- `json` CLI subcommand emitting the goal as JSON.
- `stop-hook` CLI subcommand + runaway guard env `CLAUDE_GOAL_MAX_STOP_CONTINUES` (default 500).
- Extra SQLite columns: `id` (row PK), `session_id`, `active_started_at`, `completed_at`, `source`, `metadata_json`, plus a persistent `events` audit-trail table.
- Multi-candidate session-id lookup (`TERM_SESSION_ID` / `ITERM_SESSION_ID` / `CLAUDE_SESSION_ID` / `CLAUDE_GOAL_SESSION_ID` / cwd hash) so a goal set in one Bash subshell is still reachable after cwd drift within the same terminal session.

## Platform constraints — not portable from Codex

These Codex features rely on TUI or model-loop capabilities Claude Code does not expose; they are intentionally omitted from the clone:

- Model-visible `get_goal` / `create_goal` / `update_goal` tools. Claude Code skills cannot register function tools. The clone routes the equivalent operations through Bash invocations.
- Automatic continuation baked into the model turn loop. The clone uses a Claude Code `Stop` hook, which achieves equivalent user-facing behavior with a different mechanism.
- Queued `/goal <objective>` before a thread exists (`QueuedInputAction::ParseSlash`). Claude Code does not queue slash invocations.
- Plan-mode gating (`should_ignore_goal_for_mode`). Claude Code has no analogous mode.
- Auto-pause on `TurnAbortReason::Interrupted`. Claude Code has no interrupt hook for this path.
- Thread-resume restoration of wall-clock accounting. There is no long-lived session object in Claude Code skills.
- OpenTelemetry metrics (`codex.goal.created` / `.completed` / `.budget_limited`, histograms for token count and duration).
- TUI-specific surfaces: the `Goal unmet` / `Goal abandoned` / `Pursuing goal (X)` footer indicator, the "Replace goal?" popup, the resume-paused-goal selection view.

## Data model

Observed Codex schema (`0029_thread_goals.sql`):

```
thread_goals(thread_id PK FK→threads.id, goal_id, objective, status CHECK, token_budget NULL, tokens_used, time_used_seconds, created_at_ms, updated_at_ms)
```

Clone schema (`goals.sqlite`):

```
goals(id PK, session_id UNIQUE, goal_id, objective, status CHECK, token_budget NULL, tokens_used, time_used_seconds, active_started_at, created_at, updated_at, completed_at, source, metadata_json)
events(id PK, goal_id, session_id, event, detail, created_at)
```

The clone stores seconds (not milliseconds) and carries extra bookkeeping columns; the behavior around replace / update / budget_limited promotion matches Codex exactly.
