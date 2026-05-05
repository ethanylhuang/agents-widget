# M2 Architect Artifact - Focused Agent List And Attention Badge

## Problem Restatement
M2 refines the existing native macOS menu bar app after the M1 MVP and M1.5 energy work. The app must default to showing only coding-agent tasks that are currently attached to open Terminal.app sessions, while still letting the user switch to all known recent tasks. The row UI must become cleaner: project folder name is the dominant title, Codex/OpenCode session title is clearly secondary, runtime and token usage are easier to scan, and row-level money, idle time, terminal location, active tool, and provider sparkle/code icons are removed.

M2 also fixes the weak M1/M1.5 status model. The current implementation cannot reliably distinguish "the agent is actively working" from "the live agent is waiting for the user"; M2 must make `running` versus `idle` robust, explicit, test-covered, and cheap. Performance gains at the cost of wrong status are a failure condition.

M2 also introduces an attention concept. The menu bar item must show a small red count for tasks that need user attention, including likely input needed, stuck/error states, and newly completed tasks.

---

## ASSUMPTIONS
1. M1 has already produced the Swift Package structure shown in `M1_IMPLEMENTATION_PLAN.md`.
2. The current app target is SwiftUI/AppKit on macOS 14+ using `MenuBarExtra(...).menuBarExtraStyle(.window)`.
3. "Active" means "currently backed by a local Codex/OpenCode process attached to a Terminal TTY", represented by `AgentSummary.terminalTarget != nil` or equivalent PID+TTY evidence.
4. The default view filter is Active. The user can switch to All in the menu window.
5. The app continues to read all recent sessions internally so attention counts and the All filter work, but rows hidden by the Active filter are not shown by default.
6. Historical completed sessions must not all create red badge counts. Completion attention is only for sessions observed transitioning from running/idle/stuck to complete while this app is running, or for sessions with a retained prior terminal association from this app session.
7. Row-level provider-recorded `costUSD` may remain in the normalized model for parser compatibility, but it must not be displayed in agent rows.
8. "Token cost" in the row means token consumption/count, not dollar price.
9. No raw transcript text should be displayed. Session titles must stay truncated and sanitized as in M1.
10. M2 status semantics are authoritative and replace the M1.5 shortcut that treated any live matched process as `running`.
11. `idle` means a live terminal-backed agent is not currently executing a model turn or tool call and is likely waiting for user input. Idle is an attention state, not a failure state.
12. `running` means there is fresh local evidence of active model/tool work in progress. A live process alone is not enough to call a task `running`.
13. `unknown` must be used when local evidence is insufficient. Do not silently coerce ambiguous process-only rows to `running` or `idle`.
14. Robust status detection must preserve M1.5 energy constraints: no deep scans on menu open, no per-row process polling loops, no transcript rereads when append caches prove unchanged, and no external network calls.

---

## IN_SCOPE
- `Sources/AgentsWidgetApp/AgentsWidgetApp.swift` - replace the static menu bar label with a custom label that can show a red attention count and start monitoring on launch, not only when the menu opens.
- `Sources/AgentsWidgetCore/Models/AgentSummary.swift` - add attention metadata and display/filter support types while preserving the M1 fields needed by parsers and status derivation.
- `Sources/AgentsWidgetCore/Models/AgentStatusEvidence.swift` - new lightweight evidence model for status classification, or equivalent internal types if a separate file is not needed.
- `Sources/AgentsWidgetCore/Services/AgentStatusClassifier.swift` - new pure classifier that owns the authoritative running/idle/stuck/complete/error/unknown decision tree.
- `Sources/AgentsWidgetCore/Services/AgentMonitor.swift` - maintain all discovered agents, invoke the status classifier after provider/process merge, derive attention reasons, expose active/all filtered rows or filter helpers, and track prior status/terminal-backed state for completion attention.
- `Sources/AgentsWidgetCore/Support/ProcessRunner.swift` - move the existing internal `ProcessRunner`, `PipeDrain`, and `ProcessError` out of `ProcessSnapshotProvider.swift` so process execution is shared safely.
- `Sources/AgentsWidgetCore/Support/Diagnostics.swift` - keep local diagnostics clear and non-blocking.
- `Sources/AgentsWidgetCore/Support/Formatters.swift` - add compact runtime and token formatters; keep existing formatter behavior where tests still require it.
- `Sources/AgentsWidgetCore/Views/MenuBarStatusLabel.swift` - new menu bar label view with SF Symbol terminal mark and red count badge when attention count is greater than zero.
- `Sources/AgentsWidgetCore/Views/MenuBarRootView.swift` - add Active/All segmented filter, display filtered rows, and adjust status summary for attention.
- `Sources/AgentsWidgetCore/Views/AgentRowView.swift` - redesign each row around status dot, prominent project folder, secondary session title, runtime, and token usage only.
- `Tests/AgentsWidgetTests/AgentMonitorTests.swift` - add filter and attention transition tests.
- `Tests/AgentsWidgetTests/AgentStatusClassifierTests.swift` - add exhaustive status truth-table coverage for live process, provider state, active tool, fresh activity, stale activity, completion, error, and ambiguity cases.
- `Tests/AgentsWidgetTests/CodexSessionStoreStatusEvidenceTests.swift` - add fixture-driven coverage for Codex evidence extraction used by running/idle classification.
- `Tests/AgentsWidgetTests/OpenCodeSessionStoreStatusEvidenceTests.swift` - add fixture-driven coverage for OpenCode evidence extraction used by running/idle classification.
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
- Adding third-party Swift dependencies.

---

## ARCHITECTURE & DESIGN

### Current Evidence
Local inspection before this plan showed:

- `docs/M1_IMPLEMENTATION_PLAN.md`, `docs/M1_5_ENERGY_OPTIMIZATION_IMPLEMENTATION_PLAN.md`, and `docs/M1_5_VERIFICATION.md` exist and must be treated as prior evidence.
- `docs/M1_5_VERIFICATION.md` records the current M1.5 status shortcut: a live process matched to a non-complete session becomes `running`, an unmatched live process becomes `idle`, and stale local complete/error is overridden by live process evidence.
- The M1.5 shortcut fixed false `error`/false `idle` regressions, but it is not precise enough for M2 because it cannot prove whether a live matched agent is actively working or waiting for user input.
- `AgentRowView` currently renders a status dot plus provider SF Symbol, including `sparkles` for Codex.
- `AgentRowView.metadataLine` currently includes project basename, runtime, idle time, and TTY.
- `AgentRowView.metricsLine` currently includes tokens, row-level USD, and active tool.
- `MenuBarRootView` currently renders all `monitor.agents` with no Active/All filter.
- `AgentsWidgetApp` currently uses `MenuBarExtra("Agents Widget", systemImage: "terminal")`, so it cannot display a dynamic red count badge.

### Data Flow
1. Codex/OpenCode stores parse bounded local session deltas and emit `AgentSummary` plus status evidence. They do not infer final status alone except for explicit provider complete/error facts.
2. `ProcessSnapshotProvider` emits cached live process/TTY facts from the existing bounded process snapshot path.
3. `AgentMonitor` merges provider rows with live processes.
4. `AgentStatusClassifier` receives the merged row plus evidence and produces the authoritative status.
5. `AgentMonitor` compares the new full list to the previous full list and derives attention reasons.
6. `MenuBarStatusLabel` observes the monitor's attention count and renders the red count in the menu bar item.
7. `MenuBarRootView` defaults to `.activeTerminal` and filters rows at render time.
8. The user can switch to `.allTasks` to see all recent Codex/OpenCode sessions discovered by the M1 providers.

### Authoritative Status Contract
M2 must make the status meanings unambiguous:

- `running`: the agent is actively working. Acceptable evidence is an incomplete non-stale tool call, an open/non-final provider turn, fresh assistant/tool transcript activity, or another explicit provider-local "busy/working" signal.
- `idle`: a live terminal-backed agent has no open tool/model turn, no fresh assistant/tool activity, and no terminal provider final state. This means the agent is likely waiting for user input.
- `stuck`: the agent has an open tool/model turn that has not produced provider-local progress for longer than the stale threshold.
- `complete`: provider-local evidence says the task/session completed and there is no newer live active work for that same session.
- `error`: provider-local evidence says the task/session errored and there is no newer live active work for that same session.
- `unknown`: local evidence is insufficient or contradictory.

Hard rules:

- A live process is a prerequisite for `running`, `idle`, and `stuck`, but it is not sufficient evidence for `running`.
- A process-only row with no matched session/evidence must be `unknown`, not `idle`.
- A stale transcript timestamp alone must not make a live active turn `idle`; open activity state takes precedence.
- A stale provider `error` or `complete` must not override newer live activity evidence.
- `idle` is the status used for "needs user input"; the badge/attention system is what makes that actionable.
- Provider parser failures must degrade to `unknown` plus diagnostics, never fabricated `running`/`idle`.

### Bulletproof Running vs Idle Plan
Implement status derivation as a pure, testable classifier with a documented truth table. Do not keep the current inline `AgentMonitor.status(for:hasProcess:hasSession:now:)` as the source of truth.

Evidence inputs:

- `hasLiveProcess`: from the cached process snapshot merged into the row.
- `isTerminalBacked`: `terminalTarget != nil || (pid != nil && tty != nil)`.
- `providerTerminalState`: explicit provider-local `.complete`, `.error`, `.running`, or `.unknown` facts from transcript/DB records.
- `openActivityKind`: `.modelTurn`, `.toolCall`, or `.none`.
- `openActivityStartedAt`: when the current open activity began, if known.
- `openActivityUpdatedAt`: newest provider-local progress timestamp for the open activity, if known.
- `lastAssistantOrToolActivityAt`: newest provider-local assistant/tool output timestamp, excluding user input-only writes when the provider format exposes role/type.
- `lastUserInputAt`: newest user input timestamp, if available.
- `evidenceObservedAt`: file modification time, DB row update time, or parser observation time used to make freshness decisions explicit.

Freshness thresholds:

- `freshActivityWindowSeconds = 30`: recent assistant/tool progress keeps a live row `running`.
- `staleOpenActivitySeconds = 90`: open tool/model activity with no provider-local progress becomes `stuck`.
- `idleGraceSeconds = 5`: immediately after a user input or process/session birth, keep ambiguous live rows `unknown` briefly rather than flipping straight to `idle`.

Decision order:

1. If there is no live process: return explicit provider `.error`, explicit provider `.complete`, otherwise `.unknown`.
2. If there is a live process and an open tool/model activity:
   - if `now - openActivityUpdatedAt` or `now - openActivityStartedAt` is at least `staleOpenActivitySeconds`, return `.stuck`;
   - otherwise return `.running`.
3. If there is a live process and fresh assistant/tool activity within `freshActivityWindowSeconds`, return `.running`.
4. If there is a live process and explicit provider `.error`/`.complete` is older than newer process/session activity, ignore the stale final state and continue classification.
5. If there is a live terminal-backed matched session, no open activity, no fresh assistant/tool activity, and the row is outside `idleGraceSeconds`, return `.idle`.
6. If there is a live process but no matched session/evidence, return `.unknown`.
7. Otherwise return `.unknown`.

Provider extraction requirements:

- Codex parser must distinguish user messages from assistant/tool messages when local JSONL fields make that possible.
- Codex parser must retain incomplete tool calls and any explicit open-turn/event evidence already present in JSONL.
- OpenCode parser must distinguish DB session update time from assistant/tool progress time where message/part rows make that possible.
- OpenCode parser must retain incomplete tool calls and explicit session/share/finish/error state without treating a live process as automatic `running`.
- If provider formats do not expose an explicit open model turn, use fresh assistant/tool output plus active tool state; do not invent an open turn.

Performance requirements:

- Status classification must be O(number of merged rows) over already-parsed summaries.
- Provider evidence must come from the existing cached/append-window parsing paths; menu open must not trigger deep transcript reads.
- Process CPU sampling is out of scope unless it is available from the same cached `ps` snapshot at no extra process invocation.
- No continuous polling loop may be added solely for status precision. Existing refresh/event paths may update status using cached state.
- Manual refresh may do deeper local reads, but normal menu activation must remain cached presentation only.

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

public enum AgentOpenActivityKind: String, Codable, Sendable {
    case modelTurn
    case toolCall
}

public enum ProviderTerminalState: String, Codable, Sendable {
    case running
    case complete
    case error
    case unknown
}

public struct AgentStatusEvidence: Codable, Equatable, Sendable {
    public var providerTerminalState: ProviderTerminalState
    public var openActivityKind: AgentOpenActivityKind?
    public var openActivityStartedAt: Date?
    public var openActivityUpdatedAt: Date?
    public var lastAssistantOrToolActivityAt: Date?
    public var lastUserInputAt: Date?
    public var evidenceObservedAt: Date?
}
```

Extend `AgentSummary`:

```swift
public var attentionReasons: [AgentAttentionReason]
public var statusEvidence: AgentStatusEvidence?

public var isTerminalBacked: Bool {
    terminalTarget != nil || (pid != nil && tty != nil)
}

public var needsAttention: Bool {
    !attentionReasons.isEmpty
}
```

Do not remove M1 fields from the model in M2. `idleSeconds`, `activeTool`, and `costUSD` may still be used internally for status/attention/parser compatibility, but `AgentRowView` must stop displaying them.

### Attention Rules
Apply attention reasons after `AgentStatusClassifier` has produced final status.

1. `stuck`: current status is `.stuck` and the row is currently terminal-backed.
2. `error`: current status is `.error` and the row is currently terminal-backed.
3. `completed`: current status is `.complete` and the previous refresh saw the same id as `.running`, `.idle`, or `.stuck`, or the previous refresh had the same id as terminal-backed.
4. `inputNeeded`: current row is terminal-backed, status is `.idle`, and there is no open activity in `AgentStatusEvidence`. This is intentionally conservative and must not rely on visible idle duration in the row.

Badge count is the number of unique active agents with at least one attention reason, plus newly completed tasks observed from a previous active state. Inactive historical error rows do not count. If one task is both `stuck` and `inputNeeded`, it counts once.

Sort visible rows with attention first, then status order `stuck`, `running`, `idle`, `error`, `complete`, `unknown`, then newest activity descending.

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

### Formatting
Add or reuse pure formatters:

```swift
formatCompactDuration(_:) -> String      // "14m", "2h 14m", "3d 02h"
formatCompactTokenCount(_:) -> String    // "834 tok", "832.6k tok", "1.2M tok"
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
- Remove `activeTool` and `hasCost` from smoke row output unless needed for parser smoke debugging.

### `Sources/AgentsWidgetCore/Models/AgentSummary.swift`
- Add `AgentListFilter`.
- Add `AgentAttentionReason`.
- Add `AgentStatusEvidence`, `AgentOpenActivityKind`, and `ProviderTerminalState`, or keep them in `AgentStatusEvidence.swift` if a separate model file is clearer.
- Add `attentionReasons` to `AgentSummary` initializer with default `[]`.
- Add `statusEvidence` to `AgentSummary` initializer with default `nil`.
- Add `isTerminalBacked` and `needsAttention`.
- Ensure `refreshedDynamicFields(now:)` preserves attention reasons and status evidence.

### `Sources/AgentsWidgetCore/Services/AgentStatusClassifier.swift`
- Implement a pure `AgentStatusClassifier` with injectable thresholds:
  - `freshActivityWindowSeconds`
  - `staleOpenActivitySeconds`
  - `idleGraceSeconds`
- Expose one pure function equivalent to:

```swift
struct AgentStatusClassifier {
    func classify(_ agent: AgentSummary, hasLiveProcess: Bool, hasMatchedSession: Bool, now: Date) -> AgentStatus
}
```

- Keep all status precedence in this file. Do not duplicate partial status rules in provider stores or views.
- Treat `activeTool` as backward-compatible evidence by translating incomplete tools into `AgentStatusEvidence.openActivityKind == .toolCall` when providers have not populated the new evidence field.
- Return `.unknown` for contradictory evidence and include a diagnostic if the contradiction is parser-visible.

### `Sources/AgentsWidgetCore/Services/AgentMonitor.swift`
- Add published properties:
  - `@Published public private(set) var attentionCount: Int = 0`
- Track previous state:
  - `previousStatusesByID: [String: AgentStatus]`
  - `previousTerminalBackedIDs: Set<String>`
- Add pure helpers:
  - `filteredAgents(_ agents: [AgentSummary], filter: AgentListFilter) -> [AgentSummary]`
  - `applyAttention(to agents:previousStatuses:previousTerminalBackedIDs:) -> [AgentSummary]`
  - `attentionReasons(for:previousStatus:wasTerminalBacked:) -> [AgentAttentionReason]`
- Replace calls to the current inline `status(for:hasProcess:hasSession:now:)` with `AgentStatusClassifier`.
- Remove or demote the inline `status(for:hasProcess:hasSession:now:)` helper so there is exactly one status decision path.
- Preserve M1.5 live-process precedence over stale complete/error, but only when newer live activity evidence exists.
- Keep provider merging logic local-only and read-only.

### `Sources/AgentsWidgetCore/Services/CodexSessionStore.swift`
- Populate `AgentStatusEvidence` from the same bounded JSONL parsing already used for summary metadata.
- Track the newest non-user assistant/tool activity timestamp separately from file modification time.
- Track newest user input timestamp separately so a just-submitted prompt can remain `unknown` during `idleGraceSeconds`.
- Convert incomplete Codex tool/function-call state into `openActivityKind == .toolCall` with started/updated timestamps.
- Convert explicit Codex completion/error events into `providerTerminalState`.
- Do not classify a live Codex session as `running` only because the process exists.
- Preserve append-window cache behavior; unchanged large JSONL files must not be reread for status evidence.

### `Sources/AgentsWidgetCore/Services/OpenCodeSessionStore.swift`
- Populate `AgentStatusEvidence` from the same SQLite reads already used for session metadata.
- Distinguish session `updatedAt` from assistant/tool progress when message/part rows expose role/type/status.
- Convert incomplete OpenCode tool parts into `openActivityKind == .toolCall` with started/updated timestamps.
- Convert explicit OpenCode finish/error state into `providerTerminalState`.
- Do not classify a live OpenCode session as `running` only because the process exists.
- Keep SQLite query count bounded; M2 status evidence must not add an unbounded per-session query loop.

### `Sources/AgentsWidgetCore/Support/ProcessRunner.swift`
- Move `ProcessRunner`, `PipeDrain`, and `ProcessError` here.
- Leave behavior unchanged from M1.
- Remove duplicate definitions from `ProcessSnapshotProvider.swift`.

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
  - Status truth table proves live matched process alone is not `running`.
  - Status truth table proves process-only unmatched rows are `unknown`.
  - Status truth table proves fresh assistant/tool activity with a live process is `running`.
  - Status truth table proves live terminal-backed matched session with no open/fresh activity is `idle`.
  - Status truth table proves idle terminal-backed means input-needed attention.
  - Status truth table proves incomplete fresh tool is `running`.
  - Status truth table proves stale incomplete tool is `stuck`.
  - Status truth table proves stale provider `error` does not override newer live activity.
  - Status truth table proves explicit complete/error without live process stays complete/error.
  - Active filter returns only terminal-backed agents.
  - All filter returns terminal-backed and historical sessions.
  - Badge count counts one agent once even with multiple reasons.
  - Stuck/error agents produce attention.
  - Idle terminal-backed agent with no active tool produces input-needed attention.
  - Completed agent only produces attention on observed transition or prior terminal-backed state.
  - Historical complete agent with no previous state does not produce attention.
  - Row display model excludes TTY, idle time, active tool, and USD.
  - Codex fixture where last event is user input and no open activity classifies as `idle`.
  - Codex fixture with fresh assistant/tool output classifies as `running`.
  - OpenCode fixture where last event is user input and no open activity classifies as `idle`.
  - OpenCode fixture with fresh assistant/tool output classifies as `running`.
---

## VERIFICATION / SUCCESS CRITERIA

### Required Commands
Run these before implementation:

```bash
pwd
swift --version
xcodebuild -version
```

Run these after implementation:

```bash
swift test
swift build -c debug --product agents-widget
scripts/build-app.sh
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json
build/Agents\ Widget.app/Contents/MacOS/agents-widget --profile-refresh
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
  - per-row `status` values produced by `AgentStatusClassifier`,
  - status-evidence diagnostics when evidence is missing or contradictory.
- Status classifier tests cover every row in the decision order truth table.
- Parser fixture tests prove user-input-only terminal-backed sessions classify as `idle`, fresh assistant/tool activity classifies as `running`, stale open activity classifies as `stuck`, and ambiguous process-only rows classify as `unknown`.
- Warm `--profile-refresh` remains within the M1.5 bounded-refresh profile: no process syscalls, file parses, or bytes read when caches are warm and no provider data changed.

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
- Rows distinguish `running` from `idle` correctly for at least one real or fixture-backed active agent:
  - active model/tool work shows `running`;
  - waiting-for-user-input shows `idle` and increments attention.
- A live process with no matched session/evidence does not show `running`; it shows `unknown`.
- Rows do not show idle time, TTY, active tool, provider icon, sparkle icon, or row-level USD.
- Clicking a terminal-backed row still attempts Terminal.app focus as in M1.

### Known Limitations To Preserve In Handoff
- `inputNeeded` is heuristic unless Codex/OpenCode expose explicit waiting-for-input state in local records.
- Completed-task badge state is app-session-local in M2 and may reset on app restart.
- Active filter depends on process/TTY evidence; rows can move to All if the CLI exits and no terminal target is retained.
