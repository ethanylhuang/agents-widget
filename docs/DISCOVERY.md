# agents-widget Discovery Notes

## Purpose
Document the source evidence used to scaffold `agents-widget`. This file is planning context only. It is not implementation.

## Chain Of Custody
- Source: user request for a native macOS menu bar widget supporting Codex and OpenCode.
- Source: local workspace instructions in `/Users/ethanhuang/vibing/AGENTS.md`.
- Source: project-scaffolder skills at `/Users/ethanhuang/vibing/.agents/skills/project-scaffolder/SKILL.md` and `/Users/ethanhuang/vibing/.opencode/skills/project-scaffolder/SKILL.md`.
- Source: local command output from Codex/OpenCode binaries, process lists, session paths, and SQLite schemas.
- Source: official Apple Developer documentation for SwiftUI `MenuBarExtra`, `MenuBarExtraStyle`, AppKit `NSWorkspace`, and ApplicationServices `AXUIElement`.
- Transformation: normalized the user request and local evidence into one implementation contract and one concrete MVP milestone.
- Destination: `/Users/ethanhuang/vibing/agents-widget/AGENTS.md` and `/Users/ethanhuang/vibing/agents-widget/M1_IMPLEMENTATION_PLAN.md`.

## Local Workspace Evidence
Commands:

```bash
pwd
sed -n '1,220p' /Users/ethanhuang/vibing/.agents/skills/project-scaffolder/SKILL.md
sed -n '1,220p' .opencode/skills/project-scaffolder/SKILL.md
diff -u .agents/skills/project-scaffolder/SKILL.md .opencode/skills/project-scaffolder/SKILL.md
rg --files -g 'AGENTS.md' -g '.opencode/skills/**/SKILL.md' -g '.agents/skills/**/SKILL.md' -g 'agents-widget/**'
sed -n '1,240p' AGENTS.md
ls -la
find . -maxdepth 2 -type d -name 'agents-widget' -print
find . -maxdepth 2 -type f \( -name 'M*_IMPLEMENTATION_PLAN.md' -o -name 'AGENTS.md' \) -print
```

Findings:
- Working directory is `/Users/ethanhuang/vibing`.
- No existing `agents-widget` directory was present before scaffold creation.
- Local project doctrine requires evidence-first execution and summary blocks.
- The project-scaffolder skill requires `AGENTS.md` and `M*_IMPLEMENTATION_PLAN.md` planning artifacts.
- The `.opencode` project-scaffolder copy additionally requires an adversarial review loop. This scaffold used self-review fallback because independent subagents were not permitted by the active execution policy.

## Codex Evidence
Commands:

```bash
which codex
codex --help
find /Users/ethanhuang/.codex -maxdepth 3 -type d -print
find /Users/ethanhuang/.codex/sessions/2026/05 -maxdepth 3 -type f -print
find /Users/ethanhuang/.codex/log -maxdepth 2 -type f -print
sqlite3 /Users/ethanhuang/.codex/sqlite/codex-dev.db .tables
sqlite3 /Users/ethanhuang/.codex/sqlite/codex-dev.db .schema
jq -s 'map(.type) | unique' /Users/ethanhuang/.codex/sessions/2026/05/03/rollout-2026-05-03T23-12-48-019df19e-2c82-7dc1-b009-c812c2221c28.jsonl
jq -s 'map(keys) | add | unique' /Users/ethanhuang/.codex/sessions/2026/05/03/rollout-2026-05-03T23-12-48-019df19e-2c82-7dc1-b009-c812c2221c28.jsonl
jq -s 'map(.payload | keys) | add | unique' /Users/ethanhuang/.codex/sessions/2026/05/03/rollout-2026-05-03T23-12-48-019df19e-2c82-7dc1-b009-c812c2221c28.jsonl
jq -s 'map(select(.type == "event_msg") | .payload.type) | unique' /Users/ethanhuang/.codex/sessions/2026/05/03/rollout-2026-05-03T23-12-48-019df19e-2c82-7dc1-b009-c812c2221c28.jsonl
jq -s 'map(select(.type == "response_item") | .payload.type) | unique' /Users/ethanhuang/.codex/sessions/2026/05/03/rollout-2026-05-03T23-12-48-019df19e-2c82-7dc1-b009-c812c2221c28.jsonl
jq -s 'map(select(.type == "event_msg" and .payload.type == "token_count") | .payload.info) | .[-1]' /Users/ethanhuang/.codex/sessions/2026/05/03/rollout-2026-05-03T23-12-48-019df19e-2c82-7dc1-b009-c812c2221c28.jsonl
```

Findings:
- Codex binary path: `/opt/homebrew/bin/codex`.
- Codex CLI supports interactive sessions plus `exec`, `review`, `resume`, `fork`, `app-server`, and debug tooling.
- Codex session data exists under `/Users/ethanhuang/.codex/sessions`.
- Current session JSONL top-level keys are `payload`, `timestamp`, and `type`.
- Observed top-level event types: `event_msg`, `response_item`, `session_meta`, `turn_context`.
- Observed `event_msg` types include `agent_message`, `exec_command_end`, `task_started`, `token_count`, and `web_search_end`.
- Observed `response_item` types include `function_call`, `function_call_output`, `message`, `reasoning`, and `web_search_call`.
- Observed Codex token counts include `total_token_usage`, `last_token_usage`, and `model_context_window`.
- The Codex SQLite database at `/Users/ethanhuang/.codex/sqlite/codex-dev.db` appears related to automations/inbox, not the main interactive session list.

## OpenCode Evidence
Commands:

```bash
which opencode
opencode --help
opencode stats --help
opencode session --help
opencode export --help
find /Users/ethanhuang/.opencode -maxdepth 3 -type d -print
find /Users/ethanhuang/.local/share/opencode -maxdepth 4 -type d -print
find /Users/ethanhuang/.local/share/opencode/storage -maxdepth 3 -type f -print
find /Users/ethanhuang/.local/share/opencode/log -maxdepth 2 -type f -print
opencode session list
opencode stats --days 1 --models 5 --tools 5
find /Users/ethanhuang/.local/share/opencode -maxdepth 3 -type f -print
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db .tables
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db .schema
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db 'select count(*) from session;'
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db 'select count(*) from message;'
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db 'select id, title, directory, time_created, time_updated from session order by time_updated desc limit 5;'
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db "select distinct json_extract(data, '$.type') from part order by 1;"
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db "select distinct json_each.key from part, json_each(part.data) order by 1;"
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db "select distinct json_each.key from message, json_each(message.data) order by 1;"
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db "select data from part where json_extract(data, '$.type') = 'step-finish' order by time_updated desc limit 1;"
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db "select data from part where json_extract(data, '$.type') = 'tool' order by time_updated desc limit 1;"
```

Findings:
- OpenCode binary path: `/Users/ethanhuang/.opencode/bin/opencode`.
- OpenCode CLI exposes `stats`, `session list`, and `export`.
- `opencode session list` and `opencode stats --days 1 --models 5 --tools 5` failed locally with `Failed to run the query 'PRAGMA wal_checkpoint(PASSIVE)'`.
- OpenCode direct SQLite reads succeeded against `/Users/ethanhuang/.local/share/opencode/opencode.db`.
- Relevant tables include `session`, `message`, `part`, `todo`, `project`, and `workspace`.
- Observed count: 49 sessions and 1346 messages at discovery time.
- Latest session query returned titles, directories, and millisecond timestamps.
- Observed `part.data.type` values: `compaction`, `file`, `patch`, `reasoning`, `step-finish`, `step-start`, `text`, and `tool`.
- Observed `part.data` keys include `callID`, `cost`, `metadata`, `reason`, `state`, `time`, `tokens`, `tool`, and `type`.
- Observed `message.data` keys include `agent`, `cost`, `error`, `finish`, `model`, `modelID`, `providerID`, `role`, `summary`, `time`, `tokens`, and `tools`.
- OpenCode `step-finish` parts can include token totals and cost.
- OpenCode `tool` parts include `state.status`, `state.time.start`, optional `state.time.end`, input, metadata, output, and tool name.

## Process And Terminal Evidence
Commands:

```bash
ps aux -ww
osascript -e 'tell application "System Events" to get name of every process whose background only is false'
```

Findings:
- `ps aux -ww` showed multiple running `codex` processes with TTYs such as `s000`, `s004`, `s005`, and `s006`.
- `ps aux -ww` showed a running `opencode` process attached to a Terminal TTY.
- Terminal.app was running from `/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal`.
- The System Events AppleScript command failed with error `-10827`, so implementation must treat automation/permission failures as expected runtime conditions.

## Apple Documentation Evidence
Official sources consulted:
- SwiftUI `MenuBarExtra`: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- SwiftUI `MenuBarExtraStyle`: https://developer.apple.com/documentation/swiftui/menubarextrastyle
- AppKit `NSWorkspace`: https://developer.apple.com/documentation/AppKit/NSWorkspace
- AppKit `NSApplication.activate()`: https://developer.apple.com/documentation/appkit/nsapplication/activate%28%29
- ApplicationServices `AXUIElement`: https://developer.apple.com/documentation/applicationservices/axuielement

Findings:
- `MenuBarExtra` is the native SwiftUI scene for a persistent menu bar control.
- `MenuBarExtraStyle.window` supports richer popover-like content than a simple pull-down menu.
- `LSUIElement` can hide a utility app from the Dock/application switcher.
- `NSWorkspace` can locate and activate applications.
- `AXUIElement`/accessibility APIs are appropriate for interacting with UI elements when needed, but V1 should prefer Terminal.app scripting first.
