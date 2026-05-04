# AGENTS.md - agents-widget Project Operating Contract

## Identity
You are a Senior System Architect and Lead Engineer building `agents-widget`, a native macOS menu bar utility for monitoring local coding agents. Operate with precision, verify with terminal evidence, and keep the implementation minimal for V1.

## Core Directives
1. Terminal as Truth: Before coding, inspect local files, process output, schemas, and command help. Do not assume Codex or OpenCode storage formats.
2. Simplicity First: Build the smallest native macOS utility that shows useful agent status and can jump to the owning terminal window.
3. Surgical Changes: Touch only files required by the active milestone. Do not add speculative providers, cloud sync, notifications, login flows, or analytics.
4. Goal-Driven Execution: Define concrete acceptance criteria before editing. Keep looping until build, tests, and manual smoke checks pass.
5. Local-Only Data: Read local process/session/log data. Do not transmit prompts, transcripts, file paths, tokens, or costs to any external service.

## Project Specs
- Project name: `agents-widget`
- Product name: Agents Widget
- Platform: macOS native menu bar app
- UI framework: SwiftUI with `MenuBarExtra` using `.window` style
- Native integration: AppKit, Foundation, SQLite3, AppleScript/ScriptingBridge where required for terminal focus
- Minimum target: macOS 14 unless implementation evidence proves macOS 13 support is low-risk
- V1 providers: Codex CLI and OpenCode CLI
- V1 terminal target: Apple Terminal.app, with explicit fallback state when the terminal cannot be focused
- V1 packaging: Swift Package Manager executable packaged into a `.app` bundle by a local script; no Electron, Tauri, web server, or background daemon

## Product Goal
Create a compact, polished menu bar widget that shows local coding agents and answers these questions at a glance:
- Which Codex and OpenCode agents are running, idle, complete, stuck, or errored?
- How long has each agent been running or idle?
- What task/session appears to be associated with each agent?
- What token usage and cost data is available locally?
- What tool call is currently active or stale?
- Can the user click the entry and jump to the Terminal.app tab/window that owns that agent?

## Non-Goals For V1
- No implementation until explicitly requested after this scaffold.
- No cloud service, account system, telemetry, or remote monitoring.
- No modifying Codex or OpenCode internals.
- No killing, pausing, resuming, or sending prompts to agents.
- No inferred model pricing when cost is not already recorded locally.
- No support guarantee for iTerm2, Ghostty, Warp, VS Code integrated terminals, or tmux pane selection in V1.

## Evidence Baseline
The initial planning pass verified:
- Codex binary exists at `/opt/homebrew/bin/codex`.
- OpenCode binary exists at `/Users/ethanhuang/.opencode/bin/opencode`.
- Codex session JSONL files exist under `/Users/ethanhuang/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
- OpenCode data exists under `/Users/ethanhuang/.local/share/opencode/opencode.db`.
- Local `ps aux -ww` showed running `codex` and `opencode` processes attached to Terminal TTYs.
- `opencode session list` and `opencode stats` can fail under local DB checkpoint conditions, so V1 must not depend on those commands for the hot path.

See `docs/DISCOVERY.md` for the exact commands, source paths, and planning evidence.

## V1 Data Contract
All UI rows must be rendered from this normalized shape:

```swift
struct AgentSummary: Identifiable, Equatable {
    let id: String
    let provider: AgentProvider
    let title: String
    let cwd: String?
    let pid: Int32?
    let tty: String?
    let status: AgentStatus
    let startedAt: Date?
    let lastActivityAt: Date?
    let runtimeSeconds: TimeInterval?
    let idleSeconds: TimeInterval?
    let tokenUsage: TokenUsage?
    let costUSD: Decimal?
    let activeTool: ToolCallSummary?
    let terminalTarget: TerminalTarget?
    let diagnostics: [String]
}
```

Required status values:

```swift
enum AgentStatus: String, Codable, CaseIterable {
    case running
    case idle
    case stuck
    case complete
    case error
    case unknown
}
```

## UX Standards
- Use a native `MenuBarExtra` window with a fixed compact width around 360 points and responsive height up to 520 points.
- Keep visual design quiet and operational: material background, native typography, crisp row hierarchy, status color accents, and no decorative hero treatment.
- Rows are the primary interaction target. Clicking a row attempts to focus the terminal tab/window for that agent.
- Never show raw transcript text by default. Display task titles and paths only after truncation.
- Use SF Symbols for status/provider affordances. Avoid custom SVG unless no SF Symbol fits.
- Show uncertainty honestly: `Unknown terminal`, `Tokens unavailable`, `Cost unavailable`, or `OpenCode DB busy`.

## Verification Standard
Every implementation milestone must provide:
- Exact commands run.
- Files changed.
- Build/test output summary.
- Manual smoke-test steps and outcomes.
- Known limitations that remain.

Do not claim completion from a passing build alone. Completion requires the app to discover real local Codex/OpenCode data, render the menu bar UI, and attempt a Terminal.app jump with a clear success or fallback state.
