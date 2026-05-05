# M2 Verification Evidence - Focused Agent List And Attention Badge

Date: 2026-05-04

## Status

M2 implementation gates pass. The app now uses a pure status classifier, defaults visible rows to Terminal-backed agents, exposes Active/All filtering, derives attention counts, renders a dynamic red menu bar badge, and removes row-level USD/TTY/idle/tool/provider icons.

## Commands Run

```bash
pwd
sed -n '1,220p' /Users/ethanhuang/.codex/skills/go/SKILL.md
git status --short
rg --files
sed -n '1,260p' AGENTS.md
sed -n '1,260p' docs/M1_IMPLEMENTATION_PLAN.md
sed -n '1,320p' docs/M1_5_ENERGY_OPTIMIZATION_IMPLEMENTATION_PLAN.md
sed -n '1,760p' docs/M2_IMPLEMENTATION_PLAN.md
sed -n '1,260p' docs/M1_5_VERIFICATION.md
sed -n '1,220p' docs/M1_VERIFICATION.md
swift --version
xcodebuild -version
swift test
swift build -c debug --product agents-widget
scripts/build-app.sh
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json --smoke-terminal
build/Agents\ Widget.app/Contents/MacOS/agents-widget --profile-refresh
pgrep -fl agents-widget
scripts/run-app.sh
osascript -e 'tell application "System Events" to tell process "agents-widget" to return {description of menu bar item 1 of menu bar 2, name of menu bar item 1 of menu bar 2, value of attribute "AXPosition" of menu bar item 1 of menu bar 2, value of attribute "AXSize" of menu bar item 1 of menu bar 2}'
osascript -e 'delay 2' -e 'tell application "System Events" to tell process "agents-widget" to return {description of menu bar item 1 of menu bar 2, name of menu bar item 1 of menu bar 2, value of attribute "AXPosition" of menu bar item 1 of menu bar 2, value of attribute "AXSize" of menu bar item 1 of menu bar 2}'
swift -e 'import CoreGraphics; import Foundation; let point = CGPoint(x: 2026, y: 15); let source = CGEventSource(stateID: .hidSystemState); CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(100_000); CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(1_000_000); let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []; var found = false; for w in windows { let owner = w[kCGWindowOwnerName as String] as? String ?? ""; if owner.contains("Agents Widget") || owner.contains("agents-widget") { found = true; let name = w[kCGWindowName as String] as? String ?? ""; let layer = w[kCGWindowLayer as String] ?? ""; let bounds = w[kCGWindowBounds as String] ?? [:]; print("owner=\(owner) name=\(name) layer=\(layer) bounds=\(bounds)") } }; if !found { print("no onscreen Agents Widget windows") }'
git diff --check
date
```

SwiftPM, packaged smoke/profile, process-list, app launch, AppleScript, and synthetic-click GUI commands were run outside the sandbox where required so process discovery and menu-bar behavior matched the real app environment.

## Build And Test Evidence

- `swift --version`: Apple Swift 6.2.
- `xcodebuild -version`: Xcode 26.0.1.
- `swift test`: 78 XCTest cases passed with 0 failures.
- `swift build -c debug --product agents-widget`: debug product built successfully.
- `scripts/build-app.sh`: created `/Users/ethanhuang/agents-widget/build/Agents Widget.app`.
- `git diff --check`: no whitespace errors.

## Local Discovery And Smoke Evidence

Final packaged smoke probe with real process-table access:

- `codexSessionCount`: 12
- `openCodeSessionCount`: 49
- `processCount`: 3
- `mergedAgentCount`: 61
- `visibleActiveCount`: 3
- `attentionCount`: 2
- `diagnostics`: empty

Smoke rows included:

- Terminal-backed `Codex - opencode-grok-auth` as `idle` with `inputNeeded`.
- Terminal-backed `Codex - trip-planner` as `idle` with `inputNeeded`.
- Terminal-backed `Codex - agents-widget` as `running`.
- Historical inactive Codex/OpenCode error rows with empty `attentionReasons`.

Terminal focus smoke:

- `terminalJumpResult`: `focused`

## Refresh Profile Evidence

Final packaged `--profile-refresh`:

- Cold bounded: CPU `0.309478s`, wall `0.362665s`, files parsed `12`, process syscalls `4`, SQLite queries `17`.
- Warm bounded profile: CPU `0.006311s`, wall `0.006358s`, bytes read `0`, files parsed `0`, process syscalls `0`, SQLite queries `1`.
- Warm loop max over 20 samples: CPU `0.00666s`, wall `0.007936s`, bytes read `0`, files parsed `0`, process syscalls `0`, SQLite queries `1`.
- Manual deep profile: CPU `0.950344s`, wall `0.959388s`, bytes read `5,072,125`, files parsed `38`, SQLite queries `83`.

The warm bounded profile stays inside the M1.5 bounded-refresh requirement and adds no warm file parses, bytes read, or process syscalls.

## Manual Smoke Evidence

- `scripts/run-app.sh` launched the packaged app.
- `pgrep -fl agents-widget` reported PID `90560` running from `build/Agents Widget.app/Contents/MacOS/agents-widget`.
- Accessibility read of the corrected status menu item returned `status menu`, badge/name `2`, position `{2002, 3}`, size `{50, 24}`.
- Synthetic click of the menu bar item produced an on-screen `Agents Widget` window with bounds `{X = 2002, Y = 32, Width = 360, Height = 357}`.

## Success Criteria Audit

| Criterion | Status | Evidence |
| --- | --- | --- |
| Active/All filter defaults to active Terminal-backed rows | Pass | `visibleActiveCount` was `3` while `mergedAgentCount` was `61`; `AgentMonitor.filteredAgents` tests cover Active and All. |
| Running vs idle no longer uses live process alone | Pass | `AgentStatusClassifierTests` cover live matched idle, process-only unknown, fresh activity running, open tool running/stuck, and stale error ignored by fresh activity. |
| Attention badge counts active input-needed/stuck/error/completed | Pass | Corrected `attentionCount` was `2`; unit tests cover idle input-needed, active error/stuck attention, inactive error exclusion, transition-only completed attention, and unique-agent counts. |
| Row UI removes provider icons, idle time, TTY, active tool, and USD | Pass | `AgentRowDisplayModel` tests verify visible row text excludes TTY, active tool, and row-level cost; `AgentRowView` only renders status dot, project, session subtitle, runtime, tokens, and status. |
| Terminal.app focus still works | Pass | Packaged `--smoke-json --smoke-terminal` returned `terminalJumpResult: focused`. |
| Packaged app launches for demo | Pass | `scripts/run-app.sh` launched PID `90560`; menu window was visible after synthetic click. |

## Known Limitations

- `inputNeeded` remains heuristic because Codex/OpenCode do not expose a stable explicit waiting-for-input flag in all local records.
- Completed-task attention is app-session-local and resets when the app restarts.
- Active filtering depends on live process/TTY evidence; a row moves out of Active after its CLI exits unless a live terminal target is retained by the current app session.
