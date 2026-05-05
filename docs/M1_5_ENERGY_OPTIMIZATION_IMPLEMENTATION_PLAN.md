# M1.5 Architect Artifact -- Energy Optimization

## Problem Restatement
Agents Widget currently idles near zero Energy Impact, but user-observed Activity Monitor spikes near 100 during activation/use indicate expensive refresh paths still fire unpredictably. This milestone eliminates random high Energy Impact spikes while preserving useful menu-open status, manual refresh, and Terminal.app jump behavior.

The goal is not zero instantaneous Energy Impact. The goal is an attainable, repeatable profile: hidden work stays effectively idle, normal warm menu activation remains bounded, and any expensive work is explicit, measured, and visible as manual refresh activity.

---

## ASSUMPTIONS
1. Target platform remains native macOS 14+ with SwiftUI `MenuBarExtra`, AppKit/Foundation, SQLite3, and local-only data access.
2. Activity Monitor is the product-facing pass/fail signal; internal profile JSON and terminal CPU/idle-wake evidence are supporting evidence.
3. Slightly stale cached data is acceptable if it prevents random refresh spikes.
4. Manual refresh may perform deeper work than normal menu activation, but it must report timing and must settle quickly after completion.
5. Terminal jump metadata may be delayed or unavailable until a low-cost process snapshot can supply a trustworthy TTY target.

---

## IN_SCOPE
- `Sources/AgentsWidgetCore/Services/AgentMonitor.swift` -- throttle menu-open refreshes, avoid automatic detail refreshes from provider file events, and keep hidden mode free of timers/watchers.
- `Sources/AgentsWidgetCore/Services/AgentRefreshWorker.swift` -- preserve refresh reasons and profiling, ensure bounded/menu/manual refresh modes are explicit, and avoid repeated work when cache is valid.
- `Sources/AgentsWidgetCore/Services/ProcessSnapshotProvider.swift` -- reduce process-scan spike cost by caching recent snapshots and deferring path/cwd enrichment unless needed.
- `Sources/AgentsWidgetCore/Services/CodexSessionStore.swift` -- further reduce bounded refresh file/window limits and ensure append-only parsing remains the hot path.
- `Sources/AgentsWidgetCore/Services/OpenCodeSessionStore.swift` -- reduce bounded detail queries and rely on metadata/cache unless an active/recent candidate requires detail.
- `Sources/AgentsWidgetApp/AgentsWidgetApp.swift` -- extend smoke/profile output if needed to report spike-relevant metrics for activation loops.
- `Tests/AgentsWidgetTests/*` -- add or update tests proving hidden no-work behavior, menu-open throttling, provider-dirty marking, process-snapshot caching, and bounded refresh query/file-read limits.
- `docs/M1_5_ENERGY_OPTIMIZATION_IMPLEMENTATION_PLAN.md` -- keep this plan as the source of truth for the milestone.

---

## OUT_OF_SCOPE
- No cloud telemetry, analytics, or external power reporting.
- No support expansion to iTerm2, Ghostty, Warp, VS Code terminals, or tmux pane selection.
- No killing, pausing, resuming, or sending input to agents.
- No inferred model pricing or transcript rendering.
- No attempt to make first launch perfectly flat; brief cold-start spikes are acceptable if bounded and explainable.

---

## ARCHITECTURE & DESIGN
Use a cache-first activation path. Hidden mode must not run periodic refreshes, file-event processing, process watchers, or detail parsing. Menu open should render cached data immediately and run at most one bounded refresh unless provider state is dirty and the recent refresh throttle has expired.

Provider file events should mark dirty state only while visible, not force detail refresh. If the menu is closed, event sources should be stopped entirely. On next menu open, dirty providers may refresh through bounded mode only; manual refresh remains the explicit deep path.

Process discovery should stop being a repeated full-system syscall burst on every warm open. Reuse recent process snapshots for short intervals, scan BSD process names before path/cwd lookup, and defer expensive cwd/path enrichment until required for matching or terminal jump.

Codex and OpenCode stores should preserve current incremental/cache behavior but tighten bounded work. Codex bounded mode should parse only a small recent file set and tail/prefix windows, then append-only bytes after cache. OpenCode bounded mode should query session metadata first and details only for a minimal active/recent candidate set.

Energy Impact targets:
- Hidden idle: `0.0` most of the time; 10-minute average `<= 0.1`.
- First launch or fully cold activation: temporary peak `<= 40`, settling below `2` within 15 seconds.
- Warm menu open / normal use: peak `<= 20`; preferred `<= 10`; settling below `2` within 3 seconds.
- Manual deep refresh: peak `<= 50` only while visibly refreshing; settling below `2` within 10 seconds.
- Failure: any random spike `>= 50` outside first launch/manual refresh, or repeated warm-menu spikes `>= 25`.

---

## VERIFICATION / SUCCESS CRITERIA
1. Run `swift test`; all tests must pass.
2. Run `.build/debug/agents-widget --smoke-json`; it must discover local Codex/OpenCode data without diagnostics regressions.
3. Run `.build/debug/agents-widget --profile-refresh`; warm bounded refresh should stay under 250 ms CPU and report bytes/files/queries/syscalls.
4. Package and launch the app, then validate in Activity Monitor with `Energy Impact`, `12 hr Power`, `CPU Time`, and `Idle Wake Ups` visible.
5. Activity Monitor scenario A: hidden idle for 10 minutes. Pass if Energy Impact is usually `0.0` and 10-minute average is `<= 0.1`.
6. Activity Monitor scenario B: warm menu open/close repeated 20 times. Pass if warm opens peak `<= 20`, preferred `<= 10`, and settle below `2` within 3 seconds.
7. Activity Monitor scenario C: menu left open while Codex/OpenCode write locally. Pass if no random spike `>= 50` occurs and visible refreshes remain bounded.
8. Activity Monitor scenario D: one manual deep refresh. Pass if any spike is `<= 50` and settles below `2` within 10 seconds.
9. If any target fails, optimize the highest-cost measured path first, then repeat the full verification loop until all targets pass.
