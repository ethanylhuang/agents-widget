# M2 Architect Artifact - Focused Agent List, Attention Badge, Usage Summary

## Problem Restatement
M2 refines the existing native macOS menu bar app after the M1 MVP. The app must default to showing only coding-agent tasks that are currently attached to open Terminal.app sessions, while still letting the user switch to all known recent tasks. The row UI must become cleaner: project folder name is the dominant title, Codex/OpenCode session title is clearly secondary, runtime and token usage are easier to scan, and row-level money, idle time, terminal location, active tool, and provider sparkle/code icons are removed.

M2 also introduces an attention concept. The menu bar item must show a small red count for tasks that need user attention, including likely input needed, stuck/error states, and newly completed tasks. A minimal footer summary must use local `ccusage` JSON output to show today's and this week's token and dollar consumption without making the per-agent rows about money.

---

## ASSUMPTIONS
1. M1 has already produced the Swift Package structure shown in `M1_IMPLEMENTATION_PLAN.md`.
2. The current app target is SwiftUI/AppKit on macOS 14+ using `MenuBarExtra(...).menuBarExtraStyle(.window)`.
3. "Active" means "currently backed by a local Codex/OpenCode process attached to a Terminal TTY", represented by `AgentSummary.terminalTarget != nil` or equivalent PID+TTY evidence.
4. The default view filter is Active. The user can switch to All in the menu window.
5. The app continues to read all recent sessions internally so attention counts and the All filter work, but rows hidden by the Active filter are not shown by default.
6. Historical completed sessions must not all create red badge counts. Completion attention is only for sessions observed transitioning from running/idle/stuck to complete while this app is running, or for sessions with a retained prior terminal association from this app session.
7. `ccusage` is available locally at `/opt/homebrew/bin/ccusage` on the current machine. The implementation must still handle the command being missing.
8. `ccusage --offline --json` must be used for the hot path so the app does not trigger network pricing fetches.
9. Row-level provider-recorded `costUSD` may remain in the normalized model for parser compatibility, but it must not be displayed in agent rows.
10. "Token cost" in the row means token consumption/count, not dollar price.
11. No raw transcript text should be displayed. Session titles must stay truncated and sanitized as in M1.

---

## IN_SCOPE
- `Sources/AgentsWidgetApp/AgentsWidgetApp.swift` - replace the static menu bar label with a custom label that can show a red attention count and start monitoring on launch, not only when the menu opens.
- `Sources/AgentsWidgetCore/Models/AgentSummary.swift` - add attention metadata and display/filter support types while preserving the M1 fields needed by parsers and status derivation.
- `Sources/AgentsWidgetCore/Models/UsageSummary.swift` - new local model for today/week `ccusage` totals.
- `Sources/AgentsWidgetCore/Services/AgentMonitor.swift` - maintain all discovered agents, derive attention reasons, expose active/all filtered rows or filter helpers, track prior status/terminal-backed state for completion attention, and refresh usage summary on a slower cadence.
- `Sources/AgentsWidgetCore/Services/CCUsageSummaryService.swift` - new read-only local service that invokes `ccusage` with `--json --offline`, parses daily/weekly totals, and returns diagnostics on missing/busy/invalid command output.
- `Sources/AgentsWidgetCore/Support/ProcessRunner.swift` - move the existing internal `ProcessRunner`, `PipeDrain`, and `ProcessError` out of `ProcessSnapshotProvider.swift` so `CCUsageSummaryService` can reuse the same safe process execution path.
- `Sources/AgentsWidgetCore/Support/Diagnostics.swift` - add `ccusage` diagnostics and remove UI dependency on `Diagnostics.costUnavailable` where no longer displayed.
- `Sources/AgentsWidgetCore/Support/Formatters.swift` - add compact runtime, token, and usage-money formatters; keep existing formatter behavior where tests still require it.
- `Sources/AgentsWidgetCore/Views/MenuBarStatusLabel.swift` - new menu bar label view with SF Symbol terminal mark and red count badge when attention count is greater than zero.
- `Sources/AgentsWidgetCore/Views/MenuBarRootView.swift` - add Active/All segmented filter, display filtered rows, adjust status summary for attention, and add minimal bottom usage summary.
- `Sources/AgentsWidgetCore/Views/AgentRowView.swift` - redesign each row around status dot, prominent project folder, secondary session title, runtime, and token usage only.
- `Tests/AgentsWidgetTests/AgentMonitorTests.swift` - add filter and attention transition tests.
- `Tests/AgentsWidgetTests/CCUsageSummaryServiceTests.swift` - add fixture-driven parser tests for daily array output, weekly object output, empty output, malformed output, and missing command diagnostics.
- `Tests/AgentsWidgetTests/FormatterTests.swift` - add compact runtime/token/money formatter coverage used by M2.
- `Tests/AgentsWidgetTests/MenuBarRootViewTests.swift` - add pure helper tests for filtered empty-state copy and attention summary copy.
- `Tests/AgentsWidgetTests/AgentRowViewTests.swift` - add testable display-model coverage so row text excludes idle time, TTY, active tool, and USD.

---

## OUT_OF_SCOPE
- Notification Center alerts, sounds, banners, local notification permissions, or persistent notification history.
- Clearing/acknowledging notifications through a new settings UI.
- Sending input to agents, killing agents, pausing/resuming agents, or modifying Codex/OpenCode internals.
- Adding support for iTerm2, Ghostty, Warp, VS Code integrated terminals, tmux pane selection, or non-Terminal focus behavior.
- Displaying raw prompts, transcripts, full paths by default, command output, tool-call names, or terminal TTY values in rows.
- Inferring per-agent dollar cost from token counts or model pricing tables.
- Calling `ccusage` without `--offline`.
- Adding third-party Swift dependencies.

---

## ARCHITECTURE & DESIGN

### Current Evidence
Local inspection before this plan showed:

- `M1_IMPLEMENTATION_PLAN.md` is the only existing milestone plan.
- `AgentRowView` currently renders a status dot plus provider SF Symbol, including `sparkles` for Codex.
- `AgentRowView.metadataLine` currently includes project basename, runtime, idle time, and TTY.
- `AgentRowView.metricsLine` currently includes tokens, row-level USD, and active tool.
- `MenuBarRootView` currently renders all `monitor.agents` with no Active/All filter and no usage summary.
- `AgentsWidgetApp` currently uses `MenuBarExtra("Agents Widget", systemImage: "terminal")`, so it cannot display a dynamic red count badge.
- `ccusage` exists locally at `/opt/homebrew/bin/ccusage`.
- `ccusage weekly --json --offline --since 20260504 --until 20260504` returned an object with `weekly` and `totals`; `totals` included `inputTokens`, `outputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `totalTokens`, and `totalCost`.
- `ccusage daily --json --offline --since 20260504 --until 20260504` returned `[]` on the current machine, so the daily parser must accept empty arrays.

### Data Flow
1. `AgentMonitor` refreshes providers as in M1 and stores the full merged list as the source of truth.
2. `AgentMonitor` compares the new full list to the previous full list and derives attention reasons.
3. `MenuBarStatusLabel` observes the monitor's attention count and renders the red count in the menu bar item.
4. `MenuBarRootView` defaults to `.activeTerminal` and filters rows at render time.
5. The user can switch to `.allTasks` to see all recent Codex/OpenCode sessions discovered by the M1 providers.
6. `CCUsageSummaryService` refreshes on launch, manual refresh, and then at a slower interval than agent polling.
7. The footer renders a compact usage line from `UsageSummary`; failures are diagnostics, not blocking errors.

### Model Additions
Add these M2 types in `AgentSummary.swift` unless a separate small model file is cleaner:

```swift
public enum AgentListFilter: String, Codable, CaseIterable, Sendable {
    case activeTerminal
    case allTasks
}

public enum AgentAttentionReason: String, Codable, CaseIterable, Sendable {
    case inputNeeded
    case stuck
    case error
    case completed
}
```

Extend `AgentSummary`:

```swift
public var attentionReasons: [AgentAttentionReason]

public var isTerminalBacked: Bool {
    terminalTarget != nil || (pid != nil && tty != nil)
}

public var needsAttention: Bool {
    !attentionReasons.isEmpty
}
```

Do not remove M1 fields from the model in M2. `idleSeconds`, `activeTool`, and `costUSD` may still be used internally for status/attention/parser compatibility, but `AgentRowView` must stop displaying them.

Create `UsageSummary.swift`:

```swift
public struct UsagePeriodSummary: Codable, Equatable, Sendable {
    public var totalTokens: Int
    public var totalCostUSD: Decimal
}

public struct UsageSummary: Codable, Equatable, Sendable {
    public var today: UsagePeriodSummary
    public var week: UsagePeriodSummary
    public var refreshedAt: Date?
    public var diagnostics: [String]
}
```

### Attention Rules
Apply attention reasons after `AgentMonitor.merge` has derived status.

1. `stuck`: current status is `.stuck`.
2. `error`: current status is `.error`.
3. `completed`: current status is `.complete` and the previous refresh saw the same id as `.running`, `.idle`, or `.stuck`, or the previous refresh had the same id as terminal-backed.
4. `inputNeeded`: current row is terminal-backed, status is `.idle`, and there is no incomplete active tool. This is intentionally conservative and should not rely on visible idle time in the row.

Badge count is the number of unique agents with at least one attention reason. If one task is both `stuck` and `inputNeeded`, it counts once.

Sort visible rows with attention first, then existing M1 status order, then newest activity descending.

### Active/All Filter
Add `AgentListFilter.activeTerminal` and `AgentListFilter.allTasks`.

Default:

```swift
@State private var selectedFilter: AgentListFilter = .activeTerminal
```

Filter behavior:

- Active: show only `agent.isTerminalBacked == true`.
- All: show all merged agents.
- Attention count is derived from all merged agents, not only the selected filter.
- Empty Active state should be `No open Terminal agents`.
- Empty All state can remain `No local agents found`.

The filter control should be a compact SwiftUI segmented picker in the header:

```text
Active | All
```

### Row Layout
Replace the M1 row hierarchy with a quieter operational row.

Required visible row content:

- Left status color light/dot only.
- Primary title: project folder basename from `cwd`, largest and most prominent text in the row.
- Secondary title: provider-specific session/task title, clearly distinct from project folder.
- Runtime: visible compact metric.
- Tokens: visible compact metric.
- Status text can remain small, but the status color is the main status affordance.

Required removals from rows:

- Codex `sparkles` icon.
- OpenCode provider/code icon.
- Idle time.
- Terminal TTY/location.
- Repeated project name in metadata.
- Row-level USD price.
- Active tool text.

Recommended row visual shape:

```text
[status dot]  agents-widget                         2h 14m
              Codex session: focused agent list     832.6k tok
              Running
```

If `cwd` is missing, use `Unknown project` as primary. If `title` is missing, use `Codex session unavailable` or `OpenCode session unavailable` as secondary.

Implement a pure display adapter if it keeps tests simple:

```swift
struct AgentRowDisplayModel: Equatable {
    var projectTitle: String
    var sessionSubtitle: String
    var runtimeText: String
    var tokenText: String
    var statusText: String
}
```

### Menu Bar Badge
Replace the current `MenuBarExtra("Agents Widget", systemImage: "terminal")` initializer with the label initializer:

```swift
MenuBarExtra {
    MenuBarRootView(monitor: monitor)
} label: {
    MenuBarStatusLabel(attentionCount: monitor.attentionCount)
        .onAppear { monitor.start() }
}
.menuBarExtraStyle(.window)
```

`MenuBarStatusLabel` requirements:

- Shows the terminal SF Symbol or compact title mark.
- Shows no badge when `attentionCount == 0`.
- Shows a red circular badge for `1...9`.
- Shows `9+` for counts greater than 9.
- Uses white badge text, small semibold font, and fixed badge dimensions so the menu bar item does not resize erratically.

Do not implement Notification Center. This badge is the M2 notification concept.

### Usage Summary
Add `CCUsageSummaryService`:

```swift
public protocol UsageSummaryProviding: Sendable {
    func summary(now: Date) -> ProviderResult<UsageSummary>
}
```

Command policy:

- Find `ccusage` using `/usr/bin/which ccusage` or known executable paths, preferring `/opt/homebrew/bin/ccusage` when it exists.
- Run without a shell through `ProcessRunner`.
- Always include `--json` and `--offline`.
- Include `--timezone` using `TimeZone.current.identifier` when available.
- For today: `ccusage daily --json --offline --since YYYYMMDD --until YYYYMMDD --timezone <tz>`.
- For current week: `ccusage weekly --json --offline --since YYYYMMDD --until YYYYMMDD --timezone <tz>`.
- Use `Calendar.current` to compute today, week start, and week end.
- Refresh no more often than every 5 minutes unless the user clicks the refresh button.

Parser requirements:

- Daily output may be an array. Empty array means zero totals.
- Weekly output may be an object with `weekly` and `totals`.
- Accept both `totalCost` and `totalCostUSD` keys.
- Accept total token fields directly when present; otherwise sum `inputTokens`, `outputTokens`, `cacheCreationTokens`, and `cacheReadTokens`.
- Invalid JSON returns a `Diagnostics.ccusage(...)` diagnostic and zero totals.
- Missing command returns a `Diagnostics.ccusage("ccusage unavailable")` diagnostic and zero totals.

Footer UI:

```text
Today 0 tok / $0.00      Week 0 tok / $0.00
```

Keep the usage summary visually subordinate to rows:

- Caption or caption2 typography.
- Secondary foreground style.
- One line where width allows.
- No card container.
- No model breakdown, chart, or per-project breakdown in M2.

### Formatting
Add or reuse pure formatters:

```swift
formatCompactDuration(_:) -> String      // "14m", "2h 14m", "3d 02h"
formatCompactTokenCount(_:) -> String    // "834 tok", "832.6k tok", "1.2M tok"
formatUsageCostUSD(_:) -> String         // "$0.00", "$3.12"
formatProjectTitle(_:) -> String         // cwd basename, "Unknown project"
formatSessionSubtitle(provider:title:) -> String
```

Keep `formatCostUSD(_:)` if tests or parser diagnostics still use it, but remove row calls to it.

---

## FILE-BY-FILE IMPLEMENTATION SPEC

### `Sources/AgentsWidgetApp/AgentsWidgetApp.swift`
- Change from static `MenuBarExtra("Agents Widget", systemImage: "terminal")` to custom label initializer.
- Start `monitor.start()` from the always-visible label path so badge polling begins after app launch.
- Preserve `--smoke-json` and `--smoke-terminal` behavior.
- Extend `SmokeReport` with:
  - `attentionCount`
  - `visibleActiveCount`
  - `usageSummaryAvailable`
- Remove `activeTool` and `hasCost` from smoke row output unless needed for parser smoke debugging.

### `Sources/AgentsWidgetCore/Models/AgentSummary.swift`
- Add `AgentListFilter`.
- Add `AgentAttentionReason`.
- Add `attentionReasons` to `AgentSummary` initializer with default `[]`.
- Add `isTerminalBacked` and `needsAttention`.
- Ensure `refreshedDynamicFields(now:)` preserves attention reasons.

### `Sources/AgentsWidgetCore/Models/UsageSummary.swift`
- Add `UsagePeriodSummary`.
- Add `UsageSummary`.
- Add `static let zero` convenience only if tests need it.

### `Sources/AgentsWidgetCore/Services/AgentMonitor.swift`
- Add published properties:
  - `@Published public private(set) var usageSummary: UsageSummary = .zero`
  - `@Published public private(set) var attentionCount: Int = 0`
- Add dependency:
  - `usageSummaryProvider: any UsageSummaryProviding`
- Update `live()` to use `CCUsageSummaryService()`.
- Track previous state:
  - `previousStatusesByID: [String: AgentStatus]`
  - `previousTerminalBackedIDs: Set<String>`
- Add pure helpers:
  - `filteredAgents(_ agents: [AgentSummary], filter: AgentListFilter) -> [AgentSummary]`
  - `applyAttention(to agents:previousStatuses:previousTerminalBackedIDs:) -> [AgentSummary]`
  - `attentionReasons(for:previousStatus:wasTerminalBacked:) -> [AgentAttentionReason]`
- Keep provider merging logic local-only and read-only.
- Refresh usage summary:
  - on first refresh,
  - on forced refresh,
  - when cached usage summary is older than 5 minutes.

### `Sources/AgentsWidgetCore/Services/CCUsageSummaryService.swift`
- Implement `UsageSummaryProviding`.
- Use `ProcessRunner.run(...)`, never shell interpolation.
- Add injectable executable URL and process-running closure for tests.
- Parse daily and weekly JSON in pure functions.
- Return zero usage plus diagnostics on command failure.

### `Sources/AgentsWidgetCore/Support/ProcessRunner.swift`
- Move `ProcessRunner`, `PipeDrain`, and `ProcessError` here.
- Leave behavior unchanged from M1.
- Remove duplicate definitions from `ProcessSnapshotProvider.swift`.

### `Sources/AgentsWidgetCore/Support/Diagnostics.swift`
- Add:

```swift
public static func ccusage(_ message: String) -> String {
    "ccusage: \(message)"
}
```

### `Sources/AgentsWidgetCore/Support/Formatters.swift`
- Add M2 compact formatters.
- Keep old formatters unless all references/tests are migrated.
- Update tests so row-visible strings use compact formatters.

### `Sources/AgentsWidgetCore/Views/MenuBarStatusLabel.swift`
- Render menu bar status symbol and optional red badge.
- Keep dimensions stable for counts 0, 1, 9, and 9+.
- Avoid decorative imagery.

### `Sources/AgentsWidgetCore/Views/MenuBarRootView.swift`
- Add segmented filter state and control in the header.
- Render `AgentMonitor.filteredAgents(monitor.agents, filter: selectedFilter)`.
- Change header summary to prioritize attention:
  - `2 need attention`
  - otherwise `3 active`
  - otherwise `Idle`
- Use filter-specific empty-state title.
- Add minimal usage summary above the footer controls or integrated into the footer.
- Keep refresh and quit controls.

### `Sources/AgentsWidgetCore/Views/AgentRowView.swift`
- Remove provider icon cluster entirely.
- Keep only the status dot/color light as the left affordance.
- Primary line uses project folder basename.
- Secondary line uses `Codex session: <title>` or `OpenCode session: <title>`.
- Runtime and token count are visually prominent, preferably right-aligned or rendered as compact metric text.
- Do not render:
  - `idleSeconds`
  - `tty`
  - `terminalTarget`
  - `activeTool`
  - `costUSD`
  - provider SF Symbols

### `Tests/AgentsWidgetTests`
- Add tests before broad UI wiring where possible.
- Keep tests fixture-driven and avoid reading real private session data.
- Required new/updated tests:
  - Active filter returns only terminal-backed agents.
  - All filter returns terminal-backed and historical sessions.
  - Badge count counts one agent once even with multiple reasons.
  - Stuck/error agents produce attention.
  - Idle terminal-backed agent with no active tool produces input-needed attention.
  - Completed agent only produces attention on observed transition or prior terminal-backed state.
  - Historical complete agent with no previous state does not produce attention.
  - Row display model excludes TTY, idle time, active tool, and USD.
  - `ccusage` parser handles empty daily array and weekly totals object.
  - Missing `ccusage` produces diagnostics and zero usage.

---

## VERIFICATION / SUCCESS CRITERIA

### Required Commands
Run these before implementation:

```bash
pwd
swift --version
xcodebuild -version
which ccusage
ccusage daily --help
ccusage weekly --help
ccusage daily --json --offline --since 20260504 --until 20260504
ccusage weekly --json --offline --since 20260504 --until 20260504
```

Run these after implementation:

```bash
swift test
swift build -c debug --product agents-widget
scripts/build-app.sh
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json
scripts/run-app.sh
```

### Automated Success Criteria
- `swift test` exits 0.
- `swift build -c debug --product agents-widget` exits 0.
- `scripts/build-app.sh` creates `build/Agents Widget.app`.
- Smoke JSON reports:
  - nonzero `mergedAgentCount` when local sessions exist,
  - `visibleActiveCount` equal to terminal-backed rows only,
  - `attentionCount`,
  - usage summary fields or clear `ccusage` diagnostics.

### Manual Smoke Criteria
- App launches as a menu bar app with no Dock icon.
- Menu bar label shows no red badge when no task needs attention.
- Menu bar label shows a red badge count when a fixture or real state has stuck/error/input-needed/newly-completed tasks.
- Opening the menu defaults to Active.
- Active shows only Terminal-backed Codex/OpenCode rows.
- Switching to All shows historical/recent non-active tasks.
- Rows show project folder as the most prominent text.
- Rows show Codex/OpenCode session title as a smaller, clearly distinct subtitle.
- Rows show runtime and token usage prominently.
- Rows do not show idle time, TTY, active tool, provider icon, sparkle icon, or row-level USD.
- Bottom usage summary is present, one-line/minimal, and shows today/week tokens and dollars from `ccusage` or a clear non-fatal diagnostic.
- Clicking a terminal-backed row still attempts Terminal.app focus as in M1.

### Known Limitations To Preserve In Handoff
- `inputNeeded` is heuristic unless Codex/OpenCode expose explicit waiting-for-input state in local records.
- `ccusage` measures Claude Code usage, not necessarily Codex/OpenCode usage, unless the local `ccusage` data source includes those tools.
- Completed-task badge state is app-session-local in M2 and may reset on app restart.
- Active filter depends on process/TTY evidence; rows can move to All if the CLI exits and no terminal target is retained.
