# M1 Architect Artifact - Native Menu Bar MVP

## Problem Restatement
Build V1 of `agents-widget`: a native macOS menu bar utility that lists local Codex and OpenCode coding-agent sessions, shows runtime/status/token/cost/tool-call context where locally available, and lets the user click an entry to jump to the Terminal.app tab/window that owns the running agent.

This plan is for an execution-only implementation agent. It intentionally decides the architecture, file layout, data models, commands, and verification gates. Do not implement extra providers or speculative automation.

---

## ASSUMPTIONS
1. The implementation runs on macOS with Xcode command-line tools installed.
2. Swift 6 or newer is available through `swift` and can compile SwiftUI/AppKit macOS code.
3. `MenuBarExtra` is available on the target macOS. Apple documents it as a SwiftUI scene for persistent menu bar controls.
4. The app is local-only and may read user-owned files under `~/.codex` and `~/.local/share/opencode`.
5. Codex sessions are JSONL files under `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
6. OpenCode sessions are stored in `~/.local/share/opencode/opencode.db` with `session`, `message`, and `part` tables.
7. Running CLI agents can be detected from local process output by matching process names `codex` and `opencode`.
8. Terminal jumping targets Apple Terminal.app first because current local evidence shows running agents attached to Terminal TTYs.
9. Terminal.app automation may require user-granted macOS Automation and/or Accessibility permissions. V1 must handle denial gracefully.
10. Cost is displayed only when a provider records a numeric cost locally. Do not infer cost from model pricing tables in V1.

---

## DECISIONS ALREADY MADE
- Build a native SwiftUI/AppKit macOS app, not Electron, Tauri, or a web UI. This satisfies the native macOS requirement and keeps V1 lightweight.
- Use `MenuBarExtra(...).menuBarExtraStyle(.window)` for the primary UI. Apple documents `.window` as appropriate for richer menu bar content.
- Package as a Swift Package Manager executable plus a local `.app` bundling script. This keeps implementation terminal-driven and avoids requiring the agent to hand-edit an Xcode project.
- Poll local state every 2 seconds while the menu is open and every 10 seconds while closed. This is simple and sufficient for V1.
- Normalize Codex and OpenCode into one `AgentSummary` model before rendering. UI code must not parse provider-specific stores.
- Use read-only SQLite access for OpenCode. Do not depend on `opencode session list` or `opencode stats` because local evidence showed both commands can fail on `PRAGMA wal_checkpoint(PASSIVE)`.
- Use local session files/DB plus process/TTY evidence. Do not call any network API.
- Implement Terminal.app jumping by matching the process TTY to Terminal tabs' `tty` property through AppleScript. If automation fails, activate Terminal.app and show a diagnostic.
- Treat "stuck" as a stale active tool call: a tool/function call started, has no completed output/end record, and is older than 90 seconds.

---

## IN_SCOPE
- `Package.swift` - Swift package manifest with a testable core target and a macOS executable target.
- `Sources/AgentsWidgetApp/AgentsWidgetApp.swift` - SwiftUI app entry point with `MenuBarExtra`.
- `Sources/AgentsWidgetCore/Views/MenuBarRootView.swift` - top-level menu bar popover/window UI.
- `Sources/AgentsWidgetCore/Views/AgentRowView.swift` - compact row view for each agent.
- `Sources/AgentsWidgetCore/Models/AgentSummary.swift` - normalized provider/status/token/tool/terminal models.
- `Sources/AgentsWidgetCore/Services/AgentMonitor.swift` - periodic refresh orchestration and state publishing.
- `Sources/AgentsWidgetCore/Services/ProcessSnapshotProvider.swift` - process, runtime, TTY, and cwd collection.
- `Sources/AgentsWidgetCore/Services/CodexSessionStore.swift` - Codex JSONL parser and summarizer.
- `Sources/AgentsWidgetCore/Services/OpenCodeSessionStore.swift` - OpenCode SQLite parser and summarizer.
- `Sources/AgentsWidgetCore/Services/TerminalJumpService.swift` - Terminal.app focus behavior.
- `Sources/AgentsWidgetCore/Support/Formatters.swift` - runtime, token, cost, and path formatting.
- `Sources/AgentsWidgetCore/Support/Diagnostics.swift` - diagnostic strings and non-fatal provider errors.
- `Resources/Info.plist` - app metadata, `LSUIElement`, usage descriptions for automation/accessibility.
- `scripts/build-app.sh` - builds the Swift executable and packages `Agents Widget.app`.
- `scripts/run-app.sh` - builds if needed and opens the packaged app.
- `Tests/AgentsWidgetTests/*` - parser, formatter, process matching, status derivation, and terminal-script generation tests.

---

## OUT_OF_SCOPE
- iTerm2, Ghostty, Warp, VS Code integrated terminal, tmux pane switching, and remote terminal selection.
- Editing, sending input to, pausing, killing, resuming, or managing agents.
- Notifications, menu bar badges beyond a compact count/status icon, Launch at Login, Sparkle updates, settings windows, and preferences panes.
- Cloud sync, remote dashboards, shared state, telemetry, or external API calls.
- Exact cost estimation for Codex when only token counts are present.
- Full transcript browsing or raw prompt display.
- Dependence on the OpenCode CLI hot path for session/status reads.

---

## ARCHITECTURE & DESIGN

### Runtime Architecture
Use one app process with four layers:

1. App/UI layer
   - `AgentsWidgetApp` owns the `MenuBarExtra`.
   - `MenuBarRootView` observes `AgentMonitor`.
   - `AgentRowView` renders one `AgentSummary` and calls `TerminalJumpService.jump(to:)` on click.

2. Monitor layer
   - `AgentMonitor` is an `@MainActor ObservableObject`.
   - It owns a `Timer` or async loop.
   - It calls providers concurrently, merges summaries, sorts them, and publishes `[AgentSummary]`.

3. Provider layer
   - `ProcessSnapshotProvider` returns running process records for `codex` and `opencode`.
   - `CodexSessionStore` returns recent Codex summaries from JSONL files.
   - `OpenCodeSessionStore` returns recent OpenCode summaries from SQLite.

4. Native integration layer
   - `TerminalJumpService` handles Terminal.app focusing.
   - `Formatters` keeps display formatting deterministic and testable.

### Data Flow
1. Refresh starts.
2. `ProcessSnapshotProvider` runs `/bin/ps` and `/usr/sbin/lsof` for candidate PIDs.
3. `CodexSessionStore` scans recent JSONL files, parses only the newest bounded set, and emits session summaries.
4. `OpenCodeSessionStore` opens SQLite read-only with a short busy timeout and emits session summaries.
5. `AgentMonitor` matches sessions to processes using provider, cwd, process start time, session update time, and TTY where available.
6. `AgentMonitor` derives `running`, `idle`, `stuck`, `complete`, `error`, or `unknown`.
7. UI renders rows. Row click calls `TerminalJumpService` with the row's `tty`.

### Normalized Models
Create these exact types in `Models/AgentSummary.swift`:

```swift
enum AgentProvider: String, Codable, CaseIterable {
    case codex
    case opencode
}

enum AgentStatus: String, Codable, CaseIterable {
    case running
    case idle
    case stuck
    case complete
    case error
    case unknown
}

struct TokenUsage: Codable, Equatable {
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
    var reasoningOutputTokens: Int?
    var totalTokens: Int?
}

struct ToolCallSummary: Codable, Equatable {
    var id: String?
    var name: String
    var status: String
    var startedAt: Date?
    var completedAt: Date?
    var ageSeconds: TimeInterval?
}

struct TerminalTarget: Codable, Equatable {
    var appName: String
    var tty: String
    var pid: Int32
}

struct AgentSummary: Identifiable, Codable, Equatable {
    var id: String
    var provider: AgentProvider
    var title: String
    var cwd: String?
    var pid: Int32?
    var tty: String?
    var status: AgentStatus
    var startedAt: Date?
    var lastActivityAt: Date?
    var runtimeSeconds: TimeInterval?
    var idleSeconds: TimeInterval?
    var tokenUsage: TokenUsage?
    var costUSD: Decimal?
    var activeTool: ToolCallSummary?
    var terminalTarget: TerminalTarget?
    var diagnostics: [String]
}
```

### Status Rules
Apply these in order:

1. `stuck`: process exists and `activeTool.ageSeconds >= 90` with no completion.
2. `running`: process exists and last activity is less than 120 seconds old.
3. `idle`: process exists and last activity is 120 seconds old or older.
4. `error`: last provider-visible tool/step ended with an error, nonzero exit, or explicit error field, and no newer successful activity exists.
5. `complete`: no process exists, but a recent session exists with a stop/finish/completed terminal state.
6. `unknown`: insufficient evidence.

### Codex Provider Details
Codex source root:

```text
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
```

Initial local evidence showed top-level JSONL keys:

```text
type, timestamp, payload
```

Initial event types:

```text
session_meta, turn_context, event_msg, response_item
```

Relevant Codex payloads:
- `session_meta`: `id`, `timestamp`, `cwd`, `originator`, `cli_version`, `source`, `model_provider`.
- `turn_context`: `cwd`, `model`, `effort`, `turn_id`, and sandbox/context fields.
- `event_msg` types observed: `task_started`, `agent_message`, `token_count`, `exec_command_end`, `web_search_end`.
- `response_item` types observed: `function_call`, `function_call_output`, `message`, `reasoning`, `web_search_call`.

Codex parser requirements:
- Read files line-by-line. Do not load all historical sessions.
- Scan at most the newest 50 files by modification time in V1.
- Parse malformed lines as diagnostics, not fatal errors.
- Use `session_meta.id` as the stable session id.
- Use `session_meta.cwd` as cwd.
- Use first user message text or first task-start signal for title when available; otherwise use `Codex - <cwd basename>` or the session id suffix.
- Use latest `event_msg.type == "token_count"` `payload.info.total_token_usage` for token totals.
- Use `payload.info.last_token_usage` only for "last turn" detail if UI space allows.
- Use `event_msg.type == "exec_command_end"` and `response_item.type == "function_call_output"` to close pending tool calls.
- Consider a `response_item.type == "function_call"` pending until a matching output/end appears by `call_id`.
- Do not show full raw messages in the UI.

### OpenCode Provider Details
OpenCode source root:

```text
~/.local/share/opencode/opencode.db
```

Initial local evidence showed these relevant tables:

```text
session(id, project_id, parent_id, slug, directory, title, version, time_created, time_updated, ...)
message(id, session_id, time_created, time_updated, data)
part(id, message_id, session_id, time_created, time_updated, data)
todo(session_id, content, status, priority, position, ...)
project(id, worktree, name, ...)
```

Observed `part.data.type` values:

```text
compaction, file, patch, reasoning, step-finish, step-start, text, tool
```

Observed `part.data` keys include:

```text
callID, cost, metadata, reason, state, time, tokens, tool, type
```

Observed `message.data` keys include:

```text
agent, cost, error, finish, model, modelID, providerID, role, summary, time, tokens, tools
```

OpenCode parser requirements:
- Open SQLite with read-only mode and `sqlite3_busy_timeout(db, 250)`.
- If SQLite open/query fails, return no OpenCode rows plus a visible provider diagnostic.
- Query at most the newest 50 sessions ordered by `session.time_updated desc`.
- Use `session.id`, `title`, `directory`, `time_created`, and `time_updated` directly.
- Parse `part.data` JSON for latest `tool` entries.
- Treat a tool part as active when `state.status` is not `completed` and has no end timestamp.
- Use latest or summed `step-finish.tokens` for token display.
- Use provider-recorded `cost` from `message.data.cost` or `part.data.cost` when numeric.
- Never write to the OpenCode database.

### Process And Runtime Matching
Use `ProcessSnapshotProvider` to collect:

```swift
struct ProcessSnapshot: Equatable {
    var pid: Int32
    var parentPid: Int32
    var provider: AgentProvider
    var tty: String?
    var startedAt: Date?
    var command: String
    var cwd: String?
}
```

Implementation requirements:
- Execute `/bin/ps` without a shell using `Process`.
- Use arguments: `["-axo", "pid=,ppid=,tty=,lstart=,command="]`.
- Match command basenames exactly or command prefixes containing `/codex`, ` codex`, `/opencode`, or ` opencode`.
- Ignore helper/editor/browser processes.
- For each candidate PID, execute `/usr/sbin/lsof` with arguments `["-a", "-p", String(pid), "-d", "cwd", "-Fn"]` to find cwd where allowed.
- Convert `ps` TTY values like `s000` to Terminal.app tty values like `/dev/ttys000`.
- Use process `startedAt` for runtime when available.
- Associate a process to a session by provider and, in order: exact cwd, session update/start time nearest to process start, then newest unmatched session.
- Keep unmatched running processes as rows with title `Codex PID <pid>` or `OpenCode PID <pid>`.

### Terminal Jump
`TerminalJumpService` must expose:

```swift
enum TerminalJumpResult: Equatable {
    case focused
    case terminalActivatedOnly(String)
    case missingTTY
    case automationDenied(String)
    case failed(String)
}

protocol TerminalJumping {
    func jump(to target: TerminalTarget?) async -> TerminalJumpResult
}
```

Terminal.app behavior:
- If `target` or `target.tty` is missing, return `.missingTTY`.
- Normalize tty to `/dev/ttysNNN`.
- Run AppleScript through `/usr/bin/osascript` or `NSAppleScript`.
- Script must:
  - Activate Terminal.
  - Iterate windows and tabs.
  - Compare each tab's `tty` property to the target tty.
  - Select the matching tab and bring its window to front.
  - Return a success marker.
- If script fails with permission or automation errors, use `NSWorkspace.shared.runningApplications` to activate Terminal.app and return `.terminalActivatedOnly` or `.automationDenied`.
- UI must surface jump failure in a small diagnostic line, not a modal alert.

AppleScript shape:

```applescript
tell application "Terminal"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is "/dev/ttys000" then
        set selected tab of w to t
        set index of w to 1
        return "focused"
      end if
    end repeat
  end repeat
end tell
return "not_found"
```

### UI Specification
Menu bar item:
- Label uses SF Symbol `terminal` or `point.3.connected.trianglepath.dotted`.
- Optional compact text: number of active/stuck agents, e.g. `3` or `!1`.
- Do not show long titles in the menu bar item.

Popover/window:
- Width: 360 points.
- Max height: 520 points.
- Background: native material where available.
- Header:
  - Title `Agents`
  - Small status summary: `2 running`, `1 stuck`, or `Idle`
  - Refresh button with SF Symbol `arrow.clockwise`
- Row:
  - Provider badge: `Codex` or `OpenCode`.
  - Status dot color: green running, amber idle, red stuck/error, gray complete/unknown.
  - Main title: task/session title, one line, middle truncation.
  - Secondary line: cwd basename plus runtime/idle time.
  - Metric line: total tokens, cost if available, active tool if available.
  - Whole row is clickable and has hover highlight.
- Footer:
  - Last refresh time.
  - `Quit` button.
  - Provider diagnostic if Codex/OpenCode parsing failed.

Empty state:
- If no sessions/processes are found: show `No local agents found` and last refresh time.
- Do not include onboarding copy, marketing text, or setup instructions in the main UI.

### Formatting Rules
- Runtime under 1 hour: `12m 04s`.
- Runtime over 1 hour: `2h 14m`.
- Tokens under 1000: `834 tok`.
- Tokens 1000 or greater: `832.6k tok` with one decimal.
- Cost: `$0.042` under `$1`, `$3.12` at or above `$1`.
- Path: display basename by default; full path only in tooltip.
- Tool call: `bash 1m 32s`, `edit 18s`, or provider name if tool name missing.

---

## FILE-BY-FILE IMPLEMENTATION SPEC

### `Package.swift`
- Declare package name `agents-widget`.
- Platforms: `.macOS(.v14)`.
- Products:
  - `.executable(name: "agents-widget", targets: ["AgentsWidgetApp"])`
- Targets:
  - `.target(name: "AgentsWidgetCore", linkerSettings: [.linkedLibrary("sqlite3")])`
  - `.executableTarget(name: "AgentsWidgetApp", dependencies: ["AgentsWidgetCore"])`
  - `.testTarget(name: "AgentsWidgetTests", dependencies: ["AgentsWidgetCore"])`
- Do not declare root `Resources/Info.plist` as a SwiftPM resource. The build script copies it into the `.app` bundle.

### `Sources/AgentsWidgetApp/AgentsWidgetApp.swift`
- Import SwiftUI.
- Import `AgentsWidgetCore`.
- Define `@main struct AgentsWidgetApp: App`.
- Own `@StateObject private var monitor = AgentMonitor.live()`.
- Define one `MenuBarExtra("Agents Widget", systemImage: "terminal") { MenuBarRootView(monitor: monitor) }`.
- Apply `.menuBarExtraStyle(.window)`.
- On launch, call `monitor.start()`.

### `Sources/AgentsWidgetCore/Models/AgentSummary.swift`
- Add all normalized models specified above.
- Add computed helpers only if they are pure and tested, such as `isActionableTerminalJump`.
- Keep models Codable and Equatable.

### `Sources/AgentsWidgetCore/Services/AgentMonitor.swift`
- `@MainActor final class AgentMonitor: ObservableObject`.
- Published properties:
  - `@Published private(set) var agents: [AgentSummary] = []`
  - `@Published private(set) var lastRefreshAt: Date?`
  - `@Published private(set) var diagnostics: [String] = []`
- Dependencies:
  - `processProvider: ProcessSnapshotProviding`
  - `codexStore: CodexSessionStoring`
  - `openCodeStore: OpenCodeSessionStoring`
  - `clock: Clock` or injectable date provider.
- Methods:
  - `start()`
  - `stop()`
  - `refresh() async`
  - `merge(processes:codex:openCode:) -> [AgentSummary]`
- Sort order:
  1. `stuck`
  2. `running`
  3. `idle`
  4. `error`
  5. `complete`
  6. `unknown`
  7. newest last activity descending

### `Sources/AgentsWidgetCore/Services/ProcessSnapshotProvider.swift`
- Define `ProcessSnapshotProviding`.
- Implement `ProcessSnapshotProvider`.
- Use `Process` to run `/bin/ps` and parse fixed columns carefully.
- Parse `ps` lines as: pid, parent pid, tty, five `lstart` fields, then the remaining text as command.
- Use `Process` to run `/usr/sbin/lsof` per matched PID.
- Include parser functions that can be unit-tested with fixture strings.
- Do not use shell interpolation.

### `Sources/AgentsWidgetCore/Services/CodexSessionStore.swift`
- Define `CodexSessionStoring`.
- Implement bounded filesystem scanner:
  - Base path: `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")`.
  - Recursively inspect only `*.jsonl`.
  - Sort by modification date descending.
  - Parse max 50 files.
- Define internal structs for permissive JSON parsing.
- Extract:
  - session id
  - cwd
  - title fallback
  - created/updated timestamps
  - total token usage
  - latest tool/function call and completion state
  - diagnostics
- Never retain full transcript strings beyond the truncated title.

### `Sources/AgentsWidgetCore/Services/OpenCodeSessionStore.swift`
- Define `OpenCodeSessionStoring`.
- Use SQLite C API directly.
- Open database URI read-only:
  - Preferred: `file:/Users/.../.local/share/opencode/opencode.db?mode=ro`
  - Construct from home directory at runtime.
- Set `sqlite3_busy_timeout(db, 250)`.
- Query newest 50 sessions:
  - `select id, title, directory, time_created, time_updated from session order by time_updated desc limit 50`
- Query latest relevant parts/messages per session:
  - `select data, time_created, time_updated from part where session_id = ? order by time_updated desc limit 200`
  - `select data, time_created, time_updated from message where session_id = ? order by time_updated desc limit 50`
- Parse JSON with `JSONSerialization`.
- Extract tokens/cost/tool state as specified.
- Close the database on every refresh in V1.

### `Sources/AgentsWidgetCore/Services/TerminalJumpService.swift`
- Define `TerminalJumping` and `TerminalJumpResult`.
- Implement `TerminalJumpService`.
- Generate AppleScript from a normalized tty string.
- Escape any interpolated values even though tty values are controlled by local parsing.
- Run `/usr/bin/osascript` through `Process`.
- Activate Terminal.app using `NSWorkspace` as fallback.
- Return structured result for UI diagnostics.

### `Sources/AgentsWidgetCore/Views/MenuBarRootView.swift`
- Render `VStack(spacing: 0)` with header, optional diagnostics, scrollable rows, footer.
- Width exactly 360 points.
- Use `.buttonStyle(.plain)` for row buttons.
- Use keyboard focus defaults where possible.
- Do not add marketing/onboarding copy.

### `Sources/AgentsWidgetCore/Views/AgentRowView.swift`
- Render from `AgentSummary`.
- Whole row is a button.
- Use fixed vertical rhythm:
  - 12 point top/bottom row padding.
  - 8 point leading provider/status cluster.
  - one-line title.
  - one-line metadata.
  - one-line metrics.
- Use native colors:
  - Codex accent: blue.
  - OpenCode accent: orange.
  - Running: green.
  - Idle: yellow/amber.
  - Stuck/error: red.
  - Complete/unknown: secondary gray.

### `Sources/AgentsWidgetCore/Support/Formatters.swift`
- Implement pure functions:
  - `formatDuration(_:)`
  - `formatTokenCount(_:)`
  - `formatCostUSD(_:)`
  - `formatPathBasename(_:)`
  - `formatLastRefresh(_:)`
- Unit-test edge cases.

### `Resources/Info.plist`
- Set bundle identifier: `com.local.agents-widget`.
- Set display name: `Agents Widget`.
- Set `LSUIElement` to `true` so the app does not appear in the Dock.
- Include Apple event usage text if required by the current SDK:
  - Purpose: focus the Terminal.app tab that owns a selected local coding agent.

### `scripts/build-app.sh`
- Use strict shell mode.
- Run `swift build -c debug --product agents-widget`.
- Create `build/Agents Widget.app/Contents/MacOS`.
- Copy `.build/debug/agents-widget` to `build/Agents Widget.app/Contents/MacOS/agents-widget`.
- Copy `Resources/Info.plist` to `build/Agents Widget.app/Contents/Info.plist`.
- Print the final app path.

### `scripts/run-app.sh`
- Call `scripts/build-app.sh`.
- Run `open "build/Agents Widget.app"`.

### `Tests/AgentsWidgetTests`
Add focused tests:
- `CodexSessionStoreTests`
  - Parses `session_meta`.
  - Parses `token_count`.
  - Detects pending function call as active tool.
  - Marks function call complete when output appears.
  - Ignores malformed JSONL line and records diagnostic.
- `OpenCodeSessionStoreTests`
  - Parses session row fields.
  - Parses `step-finish` tokens/cost.
  - Parses active `tool` state.
  - Handles database unavailable as diagnostic.
- `ProcessSnapshotProviderTests`
  - Parses `ps` line for Codex.
  - Parses `ps` line for OpenCode.
  - Normalizes `s000` to `/dev/ttys000`.
  - Does not match unrelated processes containing the words in arguments only.
- `AgentMonitorTests`
  - Merges exact cwd process/session.
  - Leaves unmatched process as visible running row.
  - Applies status priority order.
- `TerminalJumpServiceTests`
  - Generates script containing the normalized tty.
  - Returns `.missingTTY` when target is nil.
- `FormatterTests`
  - Runtime, token, cost, and path formatting.

---

## STEP-BY-STEP EXECUTION PLAN
1. Re-read `AGENTS.md`, `docs/DISCOVERY.md`, and this plan.
2. Verify the environment:
   - `pwd`
   - `swift --version`
   - `xcodebuild -version`
   - `which codex`
   - `which opencode`
   - `find ~/.codex/sessions -maxdepth 4 -type f -name 'rollout-*.jsonl'`
   - `sqlite3 ~/.local/share/opencode/opencode.db .tables`
3. Create the Swift package structure exactly as listed in `IN_SCOPE`.
4. Implement models and formatters first.
5. Add formatter and model tests.
6. Implement process snapshot parsing with fixture tests before invoking real commands.
7. Implement Codex JSONL parsing with fixtures based on the observed key shapes, not full private transcripts.
8. Implement OpenCode SQLite parsing behind a protocol; add JSON parser tests and a small temporary SQLite fixture test.
9. Implement `AgentMonitor.merge` and status derivation with tests.
10. Implement the SwiftUI views using injected preview/sample data.
11. Implement Terminal.app script generation and fallback result handling.
12. Add build and run scripts.
13. Run `swift test`.
14. Run `swift build -c debug --product agents-widget`.
15. Run `scripts/build-app.sh`.
16. Launch the app with `scripts/run-app.sh`.
17. Manually smoke test:
    - Menu bar extra appears.
    - Rows render for local Codex/OpenCode sessions or diagnostics explain why not.
    - Running local processes show runtime and TTY where available.
    - Clicking a row with a TTY attempts to focus Terminal.app.
    - Denied automation produces a visible non-fatal diagnostic.
18. Record verification output and limitations.

---

## DEPENDENCIES & COMMANDS
No third-party dependencies for V1.

Primary commands:

```bash
swift --version
xcodebuild -version
swift test
swift build -c debug --product agents-widget
scripts/build-app.sh
scripts/run-app.sh
```

Local evidence commands for manual verification:

```bash
which codex
which opencode
find /Users/ethanhuang/.codex/sessions -maxdepth 4 -type f -name 'rollout-*.jsonl'
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db .tables
/bin/ps -axo pid=,ppid=,tty=,lstart=,command=
```

Expected success signals:
- `swift test` exits 0.
- `swift build -c debug --product agents-widget` exits 0.
- `scripts/build-app.sh` creates `build/Agents Widget.app`.
- App opens without a Dock icon.
- Menu bar window shows rows or actionable diagnostics.
- Row click returns focused, activated-only, missing-tty, or automation-denied without crashing.

---

## ADVERSARIAL REVIEW STATUS
- Reviewer: self-review fallback. An independent subagent was not used because the active execution policy only permits spawning agents when the user explicitly requests subagents or delegation.
- Iterations completed: 1.
- Material findings resolved:
  - SwiftPM target layout now separates `AgentsWidgetCore` from `AgentsWidgetApp` so tests can depend on core code without importing an executable target.
  - `Package.swift` no longer declares root `Resources/Info.plist` as a SwiftPM resource; the app bundling script owns Info.plist placement.
  - Process parsing now specifies how to handle the space-containing `lstart` field from `ps`.
- Remaining non-blockers:
  - Terminal.app automation permission cannot be proven until implementation smoke testing.
  - Exact Codex/OpenCode schemas may evolve, so parsers are deliberately permissive and diagnostic-driven.

---

## VERIFICATION / SUCCESS CRITERIA
M1 is complete only when all criteria are met:

1. The app is native macOS SwiftUI/AppKit and uses `MenuBarExtra` with `.window`.
2. The app builds from terminal commands with no GUI project setup.
3. The menu bar UI is compact, visually polished, and does not display raw transcripts.
4. Codex provider reads local JSONL data and extracts session id, cwd/title fallback, token counts, and active/stale function calls.
5. OpenCode provider reads local SQLite data and extracts session title, cwd, tokens, cost when present, and active/stale tool calls.
6. Running `codex` and `opencode` processes are detected with PID, runtime, and TTY when available.
7. Agent rows show provider, status, runtime/idle time, task/session title, token usage, cost when available, and active tool state.
8. Status derivation covers running, idle, stuck, complete, error, and unknown.
9. Clicking a row with a Terminal.app TTY attempts to focus the matching Terminal tab/window.
10. Missing permissions, locked databases, malformed JSONL, unavailable cost, and missing TTYs are non-fatal and visible as diagnostics.
11. Unit tests cover parser, merge, formatter, status, and terminal-script behavior.
12. Manual smoke test proves the app opens as a menu bar app and can handle current local Codex/OpenCode state.

---

## KNOWN RISKS
- Terminal.app automation can be denied by macOS privacy controls. The app must degrade gracefully and explain the limitation.
- Mapping a running process to a session is heuristic when cwd cannot be read. Keep unmatched process rows visible instead of hiding them.
- OpenCode CLI commands may fail even when direct read-only SQLite works. Keep the hot path on direct SQLite reads.
- Codex JSONL schema can evolve. Parser must be permissive and diagnostic-driven.
- Cost is provider-specific. V1 must not pretend unavailable cost is zero.
