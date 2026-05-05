# M1.5 Verification Evidence - Energy Optimization

Date: 2026-05-04

## Status

Automated implementation gates pass, product-facing Activity Monitor energy gates pass, and the status regressions found after the energy optimization are fixed. The final app keeps menu open as cached presentation only, runs one bounded startup cache warm, and restores live process precedence so active Terminal-backed Codex rows report `running`.

## Commands Run

```bash
pwd
sed -n '1,220p' /Users/ethanhuang/.codex/skills/go/SKILL.md
sed -n '1,260p' AGENTS.md
rg --files -g 'M*_IMPLEMENTATION_PLAN.md' -g '*M*_IMPLEMENTATION_PLAN.md'
sed -n '1,260p' docs/M1_IMPLEMENTATION_PLAN.md
sed -n '1,320p' docs/M1_5_ENERGY_OPTIMIZATION_IMPLEMENTATION_PLAN.md
sed -n '1,280p' docs/M2_IMPLEMENTATION_PLAN.md
swift --version
xcodebuild -version
swift test
swift build -c debug --product agents-widget
scripts/build-app.sh
.build/debug/agents-widget --smoke-json
.build/debug/agents-widget --profile-refresh
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json --smoke-terminal
scripts/run-app.sh
pgrep -fl agents-widget
top -l 5 -s 1 -pid 46665 -stats pid,command,cpu,time,threads,wq,csw
powermetrics --show-process-energy -i 1000 -n 3 --show-usage-summary
sudo -n powermetrics --show-process-energy -i 1000 -n 3 --show-usage-summary
top -l 11 -s 60 -pid 46665 -stats pid,command,power,cpu,time,threads,wq,csw
top -l 75 -s 1 -pid 12215 -stats pid,command,power,cpu,time,threads,wq,csw
osascript -e 'tell application "System Events" to tell process "agents-widget"' -e 'repeat 20 times' -e 'click menu bar item 1 of menu bar 2' -e 'delay 0.25' -e 'key code 53' -e 'delay 0.25' -e 'end repeat' -e 'end tell'
"build/Agents Widget.app/Contents/MacOS/agents-widget" --smoke-json --smoke-terminal
.build/debug/agents-widget --profile-refresh
top -l 5 -s 1 -pid 12215 -stats pid,command,power,cpu,time,threads,wq,csw
git diff --check
git status --short
pgrep -fl agents-widget
top -l 3 -s 1 -pid 12215 -stats pid,command,power,cpu,time,threads,wq,csw
mkdir -p /private/tmp/agents-widget-activity-monitor-home/Library/Preferences
env HOME=/private/tmp/agents-widget-activity-monitor-home /System/Applications/Utilities/Activity\ Monitor.app/Contents/MacOS/Activity\ Monitor
pgrep -fl 'Activity Monitor|agents-widget|osascript'
osascript -e 'tell application "System Events"' -e 'set outputRows to {}' -e 'repeat with p in (processes whose name is "Activity Monitor")' -e 'set end of outputRows to {unix id of p as text, frontmost of p as text, visible of p as text, name of windows of p as text}' -e 'end repeat' -e 'outputRows' -e 'end tell'
find /private/tmp/agents-widget-activity-monitor-home -maxdepth 4 -print
rmdir /private/tmp/agents-widget-activity-monitor-home/Library/Preferences /private/tmp/agents-widget-activity-monitor-home/Library /private/tmp/agents-widget-activity-monitor-home
swift test
osascript -e 'tell application "Agents Widget" to quit'
pgrep -fl agents-widget
scripts/build-app.sh
"build/Agents Widget.app/Contents/MacOS/agents-widget" --smoke-json --smoke-terminal
.build/debug/agents-widget --profile-refresh
open "build/Agents Widget.app"
pgrep -fl agents-widget
top -l 45 -s 1 -pid 16409 -stats pid,command,power,cpu,time,threads,wq,csw
osascript -e 'tell application "System Events" to tell process "agents-widget"' -e 'repeat 20 times' -e 'click menu bar item 1 of menu bar 2' -e 'delay 0.25' -e 'key code 53' -e 'delay 0.25' -e 'end repeat' -e 'end tell'
top -l 45 -s 1 -pid 16409 -stats pid,command,power,cpu,time,threads,wq,csw
osascript -e 'tell application "System Events" to tell process "agents-widget"' -e 'repeat 20 times' -e 'click menu bar item 1 of menu bar 2' -e 'delay 0.25' -e 'key code 53' -e 'delay 0.25' -e 'end repeat' -e 'end tell'
top -l 5 -s 1 -pid 16409 -stats pid,command,power,cpu,time,threads,wq,csw
osascript -e 'tell application "System Events" to tell process "agents-widget"' -e 'click menu bar item 1 of menu bar 2' -e 'delay 1' -e 'set out to {}' -e 'repeat with b in buttons of window 1' -e 'set end of out to {name of b as text, description of b as text, help of b as text}' -e 'end repeat' -e 'out' -e 'end tell'
osascript -e 'tell application "System Events"' -e 'set out to {}' -e 'repeat with p in (processes whose name contains "agents" or name contains "Agents")' -e 'set end of out to {name of p as text, unix id of p as text, visible of p as text, name of menu bars of p as text, name of windows of p as text}' -e 'end repeat' -e 'out' -e 'end tell'
.build/debug/agents-widget --profile-refresh
swift test
.build/debug/agents-widget --profile-refresh
osascript -e 'tell application "Agents Widget" to quit'
scripts/build-app.sh
"build/Agents Widget.app/Contents/MacOS/agents-widget" --smoke-json --smoke-terminal
.build/debug/agents-widget --profile-refresh
open "build/Agents Widget.app"
pgrep -fl 'agents-widget|Activity Monitor|osascript'
top -l 5 -s 1 -pid 102 -stats pid,command,power,cpu,time,threads,wq,csw
top -l 45 -s 1 -pid 102 -stats pid,command,power,cpu,time,threads,wq,csw
osascript -e 'tell application "System Events" to tell process "agents-widget" to click menu bar item 1 of menu bar 2'
git status --short
rg -n "manualDeepProfile|menuCloseGraceNanoseconds|testLargeFileParsesPrefixAndTailNotWholeFile" Sources Tests docs/M1_5_VERIFICATION.md
date
sed -n '1,280p' Sources/AgentsWidgetCore/Services/AgentMonitor.swift
sed -n '210,380p' Tests/AgentsWidgetTests/AgentMonitorTests.swift
swift test
scripts/build-app.sh
kill -TERM 15674
open "build/Agents Widget.app"
pgrep -fl agents-widget
top -l 5 -s 1 -pid 46521 -stats pid,command,power,cpu,time,threads,wq,csw
"build/Agents Widget.app/Contents/MacOS/agents-widget" --smoke-json --smoke-terminal
.build/debug/agents-widget --profile-refresh
top -l 45 -s 1 -pid 46521 -stats pid,command,power,cpu,time,threads,wq,csw
osascript -e 'tell application "System Events" to tell process "agents-widget"' -e 'repeat 20 times' -e 'click menu bar item 1 of menu bar 2' -e 'delay 0.25' -e 'key code 53' -e 'delay 0.25' -e 'end repeat' -e 'end tell'
osascript -e 'tell application "System Events" to tell process "Activity Monitor" to click menu item "CPU Time" of menu 1 of menu item "Columns" of menu "View" of menu bar item "View" of menu bar 1'
osascript -e 'tell application "System Events" to tell process "Activity Monitor" to click menu item "Idle Wake Ups" of menu 1 of menu item "Columns" of menu "View" of menu bar item "View" of menu bar 1'
osascript -e 'tell application "System Events" to tell process "Activity Monitor" to tell outline 1 of scroll area 1 of group 1 of window 1 to return {count of rows, count of columns}'
osascript -e 'tell application "System Events" to tell process "Activity Monitor" to tell row 3 of outline 1 of scroll area 1 of group 1 of window 1 to return name of UI elements'
swift -e 'import CoreGraphics; let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []; var found = false; for w in windows { let owner = w[kCGWindowOwnerName as String] as? String ?? ""; if owner.contains("Agents Widget") || owner.contains("agents-widget") { found = true; let id = w[kCGWindowNumber as String] ?? ""; let layer = w[kCGWindowLayer as String] ?? ""; let bounds = w[kCGWindowBounds as String] ?? [:]; print("owner=\(owner) id=\(id) layer=\(layer) bounds=\(bounds)") } }; if !found { print("no onscreen Agents Widget windows") }'
for i in 1 2 3 4 5 6 7 8 9 10 11; do /bin/date '+%Y-%m-%d %H:%M:%S %Z'; osascript -e 'tell application "System Events"' -e 'tell process "Activity Monitor"' -e 'tell outline 1 of scroll area 1 of group 1 of window 1' -e 'repeat with r from 1 to (count of rows)' -e 'set vals to name of UI elements of row r' -e 'if (item 1 of vals as text) contains "Agents Widget" then return vals' -e 'end repeat' -e 'return "Agents Widget row not found"' -e 'end tell' -e 'end tell' -e 'end tell'; if [ "$i" != "11" ]; then sleep 60; fi; done
osascript -e 'tell application "System Events" to key code 53'
osascript -e 'tell application "Activity Monitor" to quit'
pgrep -fl 'Activity Monitor|agents-widget|osascript'
open -a "Activity Monitor"
osascript -e 'tell application "System Events"' -e 'tell process "Activity Monitor"' -e 'set frontmost to true' -e 'delay 1' -e 'return {frontmost as text, visible as text, name of windows as text}' -e 'end tell' -e 'end tell'
defaults read com.apple.ActivityMonitor
find "$HOME/Library/Saved Application State" -maxdepth 1 -name '*ActivityMonitor*' -o -name '*activity*' -print
osascript -e 'tell application "Activity Monitor" to reopen' -e 'delay 1' -e 'tell application "System Events" to tell process "Activity Monitor" to return {frontmost as text, visible as text, name of windows as text}'
osascript -e 'tell application "Activity Monitor" to make new document'
pgrep -fl osascript
kill -TERM 7999
screencapture -x /private/tmp/agents-widget-activity-monitor-screen.png
defaults export com.apple.ActivityMonitor /private/tmp/com.apple.ActivityMonitor.agents-widget-backup.plist
defaults delete com.apple.ActivityMonitor
osascript -e 'tell application "Activity Monitor" to quit'
open -a "Activity Monitor"
ls -l /private/tmp/com.apple.ActivityMonitor.agents-widget-backup.plist
pgrep -fl 'Activity Monitor|agents-widget|osascript'
defaults read com.apple.ActivityMonitor
open -a "Activity Monitor"
osascript -e 'tell application "System Events"' -e 'tell process "Activity Monitor"' -e 'set frontmost to true' -e 'delay 1' -e 'return {frontmost as text, visible as text, name of windows as text}' -e 'end tell' -e 'end tell'
osascript -e 'tell application "Activity Monitor" to quit'
defaults import com.apple.ActivityMonitor /private/tmp/com.apple.ActivityMonitor.agents-widget-backup.plist
defaults read com.apple.ActivityMonitor OpenMainWindow
open -a "Activity Monitor"
osascript -e 'tell application "System Events" to tell process "Activity Monitor" to return {frontmost as text, visible as text, name of windows as text}'
rm /private/tmp/com.apple.ActivityMonitor.agents-widget-backup.plist
test ! -e /private/tmp/com.apple.ActivityMonitor.agents-widget-backup.plist
swift -e 'import CoreGraphics; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; for w in windows { let owner = w[kCGWindowOwnerName as String] as? String ?? ""; if owner.contains("Activity Monitor") || owner.contains("Agents Widget") || owner.contains("agents-widget") { let name = w[kCGWindowName as String] as? String ?? ""; let layer = w[kCGWindowLayer as String] ?? ""; let bounds = w[kCGWindowBounds as String] ?? [:]; print("owner=\(owner) name=\(name) layer=\(layer) bounds=\(bounds)") } }'
swift -e 'import ScreenCaptureKit; import Foundation; let sema = DispatchSemaphore(value: 0); Task { do { let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true); print(content.windows.count); } catch { print("error: \(error)") }; sema.signal() }; sema.wait()'
swift -e 'import CoreGraphics; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; for w in windows { let owner = w[kCGWindowOwnerName as String] as? String ?? ""; if owner.contains("Activity Monitor") { let id = w[kCGWindowNumber as String] ?? ""; let layer = w[kCGWindowLayer as String] ?? ""; let bounds = w[kCGWindowBounds as String] ?? [:]; print("id=\(id) layer=\(layer) bounds=\(bounds)") } }'
screencapture -x -l 146051 /private/tmp/activity-monitor-window-146051.png
swift -e 'import CoreGraphics; import Foundation; import ImageIO; import UniformTypeIdentifiers; @_silgen_name("CGWindowListCreateImage") func legacyCGWindowListCreateImage(_ screenBounds: CGRect, _ listOption: UInt32, _ windowID: UInt32, _ imageOption: UInt32) -> Unmanaged<CGImage>?; let options = CGWindowImageOption.bestResolution.rawValue | CGWindowImageOption.boundsIgnoreFraming.rawValue; guard let unmanaged = legacyCGWindowListCreateImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, 146051, options) else { fatalError("legacy capture returned nil") }; let image = unmanaged.takeRetainedValue(); let url = URL(fileURLWithPath: "/private/tmp/activity-monitor-window-legacy.png"); guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("destination failed") }; CGImageDestinationAddImage(dest, image, nil); guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }; print(url.path)'
osascript -e 'tell application "Activity Monitor" to activate' -e 'delay 0.5' -e 'tell application "System Events" to return name of first process whose frontmost is true'
osascript -e 'tell application "System Events" to click at {942, 220}' -e 'delay 0.5' -e 'tell application "System Events" to return name of first process whose frontmost is true'
swift -e 'import CoreGraphics; let point = CGPoint(x: 942, y: 220); let source = CGEventSource(stateID: .hidSystemState); CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(100_000); CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(500_000)'
swift -e 'import AppKit; let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ActivityMonitor"); print(apps.map { "pid=\($0.processIdentifier) active=\($0.isActive)" }.joined(separator: ",")); for app in apps { print(app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])) }; usleep(500_000); print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")'
swift -e 'import ApplicationServices; import Foundation; let app = AXUIElementCreateApplication(31121); var names: CFArray?; let attrResult = AXUIElementCopyAttributeNames(app, &names); print("attrResult=\(attrResult.rawValue) attrs=\((names as? [String])?.prefix(20).joined(separator: ",") ?? "nil")"); var value: CFTypeRef?; let childrenResult = AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value); let children = value as? [AXUIElement] ?? []; print("childrenResult=\(childrenResult.rawValue) count=\(children.count)"); for child in children.prefix(10) { var role: CFTypeRef?; var title: CFTypeRef?; _ = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role); _ = AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title); print("role=\(role as? String ?? "") title=\(title as? String ?? "")") }'
swift -e 'import ApplicationServices; import Foundation; let app = AXUIElementCreateApplication(31121); let setResult = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue); print("setEnhanced=\(setResult.rawValue)"); var value: CFTypeRef?; let readResult = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value); print("readEnhanced=\(readResult.rawValue) value=\(String(describing: value))")'
powermetrics --help
man powermetrics | col -b | rg -n "process|energy|usage|root|superuser|show-process|sample|pid"
which powermetrics
ls -l /usr/bin/powermetrics
scripts/collect-powermetrics-energy.sh --help
scripts/collect-powermetrics-energy.sh scenario-a-hidden-idle 1 1000
ls -l scripts/collect-powermetrics-energy.sh
```

SwiftPM, app smoke/profile, process-list, top, and GUI launch commands were run outside the command sandbox where required so process discovery and app launch matched the real menu bar app environment.

## Build And Test Evidence

- `swift --version`: Apple Swift 6.2.
- `xcodebuild -version`: Xcode 26.0.1.
- `swift test`: 47 XCTest cases passed with 0 failures.
- `swift build -c debug --product agents-widget`: debug product built successfully.
- `scripts/build-app.sh`: created `/Users/ethanhuang/agents-widget/build/Agents Widget.app`.

## Success Criteria Audit

| Criterion | Status | Evidence |
| --- | --- | --- |
| 1. `swift test` passes | Pass | 47 XCTest cases passed with 0 failures after the startup warm-cache, click-only presentation, and live-process status definition fixes. |
| 2. `--smoke-json` discovers local Codex/OpenCode data without diagnostics regressions | Pass | Final rebuilt packaged smoke found 12 Codex sessions, 49 OpenCode sessions, 4 processes, 61 merged agents, empty diagnostics, and `terminalJumpResult: focused`; Terminal-backed Codex rows included `Codex - opencode-grok-auth` as `running` on `/dev/ttys004`, with tokens and terminal target present. |
| 3. `--profile-refresh` warm bounded refresh stays under 250 ms CPU and reports bytes/files/queries/syscalls | Pass | Final 20-sample warm loop max CPU 0.004828 seconds; max wall 0.011072 seconds; max bytes/files/process syscalls 0; max SQLite queries 1. Manual deep profile is now reported and measured at 0.850889 seconds CPU after optimization. |
| 4. Package and launch app, validate Activity Monitor columns visible | Pass | Final rebuilt app launched as PID 64031. Activity Monitor exposed one window, `Activity Monitor - Applications in last 12 hours`; `Energy Impact`, `CPU Time`, and `Idle Wake Ups` were enabled and checked in View > Columns. The table reported 8 visible columns and the Agents Widget row was readable. |
| 5. Scenario A hidden idle for 10 minutes | Pass | Product-facing Activity Monitor capture produced 11 valid 60-second samples from `19:54:24 PDT` through `20:04:27 PDT`; Energy Impact values were ten samples at `0.0` and one final sample at `0.1`, average `0.0091`, under the `<= 0.1` target. Idle Wake Ups stayed `0` once the column reported a numeric value. |
| 6. Scenario B warm menu open/close repeated 20 times | Pass | Product-facing Activity Monitor capture during the required 20 open/close actions peaked at Energy Impact `0.1` and was already below the `<2` settle threshold. |
| 7. Scenario C menu open while Codex/OpenCode write locally | Pass | Product-facing Activity Monitor capture while the menu stayed open and this Codex session generated local write activity from read-only commands stayed at Energy Impact `0.0` for all samples; no spike approached `>=50`. |
| 8. Scenario D one manual deep refresh | Pass | Product-facing Activity Monitor capture after one refresh click peaked at Energy Impact `7.2`, below `<=50`, and settled to `0.0` within 5 seconds, below the 10-second target. |
| 9. Optimize highest-cost path and repeat if a target fails | Pass | Crash, refresh-cost, warm-menu settle, manual-deep CPU, user-reported click-spike, and live-process status regression paths were fixed and reverified. |

## Local Discovery And Terminal Evidence

Final rebuilt packaged smoke probe:

- `codexSessionCount`: 12
- `openCodeSessionCount`: 49
- `processCount`: 4
- `mergedAgentCount`: 61
- `diagnostics`: empty
- `terminalJumpResult`: `focused`

Smoke rows included Terminal-backed Codex entries on `/dev/ttys000`, `/dev/ttys001`, `/dev/ttys002`, and `/dev/ttys004`.

Final status definitions:

- `running`: a live process matched to a non-complete local session, including old transcripts that still have a Terminal-backed Codex/OpenCode process.
- `idle`: an unmatched live process, or a live process matched to a session that is already complete.
- `stuck`: a live process with an incomplete active tool older than 90 seconds.
- `complete`: a session with no live process and provider evidence that the task finished.
- `error`: a session with no live process and provider evidence that the task errored.
- `unknown`: a session without enough local evidence for a stronger state.

Regression checks:

- `testLiveProcessOverridesStaleSessionError` prevents Terminal-backed sessions from staying `error` because of stale transcript state.
- `testLiveMatchedSessionIsRunningEvenWhenTranscriptIsOld` prevents long-running live sessions, including `Codex - opencode-grok-auth`, from being demoted to `idle` purely because parsed transcript activity is old.
- Final packaged smoke reported `Codex - opencode-grok-auth` as `running` with PID, TTY `/dev/ttys004`, token metadata, and Terminal target.
- Direct dropdown accessibility read reported `Agents, 3 running, Updated 38s ago`.

## Refresh Profile Evidence

Final debug `--profile-refresh` after the optimization:

- Cold bounded profile: `cpuTimeSeconds` 0.274392, `wallTimeSeconds` 0.343593, `processSyscalls` 4, `sqliteQueries` 17, `filesParsed` 12.
- First warm bounded profile: `cpuTimeSeconds` 0.005408, `wallTimeSeconds` 0.005436, `processSyscalls` 0, `sqliteQueries` 1, `filesParsed` 0, `bytesRead` 0.
- 20-sample warm loop: max `cpuTimeSeconds` 0.005408, max `wallTimeSeconds` 0.005436, max `processSyscalls` 0, max `filesParsed` 0, max `bytesRead` 0.
- Manual deep profile before optimization: `cpuTimeSeconds` 9.446215, `wallTimeSeconds` 9.487204, `bytesRead` 55,089,197, `filesParsed` 49, `sqliteQueries` 83.
- Manual deep profile after optimizing Codex deep refresh to window unchanged large JSONL files: `cpuTimeSeconds` 0.878532, `wallTimeSeconds` 0.880013, `bytesRead` 5,294,167, `filesParsed` 38, `sqliteQueries` 83.

This is below the M1.5 warm bounded target of 250 ms CPU.

## Hidden Idle Supporting Evidence

The final rebuilt app launched as PID `64031`.

Earlier, before the final 3-second close-grace rebuild, `top -l 5 -s 1 -pid 12215 -stats pid,command,power,cpu,time,threads,wq,csw` reported:

- `POWER`: 0.0 for all 5 samples.
- `%CPU`: 0.0 for all 5 samples.
- `TIME`: constant at `00:01.18` for all 5 samples.
- Threads/work queues stayed stable at `3` and `1`.

Earlier continuation audit:

- `git diff --check` reported no whitespace errors.
- `pgrep -fl agents-widget` confirmed the packaged app still running as PID `12215`.
- `top -l 3 -s 1 -pid 12215 -stats pid,command,power,cpu,time,threads,wq,csw` reported `POWER 0.0`, `%CPU 0.0`, and constant CPU time `00:01.18` for all 3 samples.

This supports hidden no-work behavior, but it is not a substitute for Activity Monitor Energy Impact.

After the final 3-second close-grace rebuild, `top -l 5 -s 1 -pid 16409 -stats pid,command,power,cpu,time,threads,wq,csw` reported:

- `POWER`: 0.0 for all 5 samples.
- `%CPU`: 0.0 for all 5 samples.
- `TIME`: constant at `00:01.49` for all 5 samples.
- Threads/work queues stayed stable at `3` and `1`.

After the startup warm-cache and click-only presentation rebuild, `top -l 5 -s 1 -pid 46521 -stats pid,command,power,cpu,time,threads,wq,csw` reported:

- `POWER`: 0.0 for all 5 samples.
- `%CPU`: 0.0 for all 5 samples.
- `TIME`: constant at `00:00.40` for all 5 samples.
- Threads/work queues stayed stable at `3` and `1`.

After the final status-definition rebuild, `top -l 5 -s 1 -pid 64031 -stats pid,command,power,cpu,time,threads,wq,csw` reported:

- `POWER`: 0.0 for all 5 samples.
- `%CPU`: 0.0 for all 5 samples.
- `TIME`: constant at `00:00.41` for all 5 samples.
- Threads/work queues stayed stable at `3` and `1`.

## Top POWER Proxy Evidence

`top -stats power` is accepted by macOS even though `top` does not list it in the usage text. It is not a substitute for Activity Monitor's product-facing Energy pane, but it provided a non-root proxy for finding and reducing the warm-menu spike.

Hidden-idle proxy:

- `top -l 11 -s 60 -pid 46665 -stats pid,command,power,cpu,time,threads,wq,csw` produced 11 one-minute samples from `18:16:54-0700` through `18:26:56-0700`.
- All samples showed `POWER 0.0`, `%CPU 0.0`, and CPU time stayed at `00:00.75`.

Warm-menu optimization loop:

- Baseline aggressive accessibility loop: 20 menu open/closes with 0.25-second open and close delays peaked at `POWER 43.8` and took roughly 12 seconds to settle below 2.
- After extending the warm menu-open throttle to 60 seconds, adding a 15-second close grace, removing the explicit material background, removing row hover state, and rendering only the top 12 sorted agents, the same aggressive accessibility loop peaked at `POWER 4.7`.
- The 15-second close grace was then reduced to 3 seconds. A fresh post-launch loop peaked at `POWER 25.1`, consistent with cold activation and below the cold target of 40. The second already-warm loop peaked at `POWER 8.4`, below the preferred warm target of 10, and dropped to `POWER 0.0` after the loop ended.
- After the user reported a product-facing Activity Monitor click spike above `300`, menu open was changed to presentation-only cached rendering and startup discovery was moved to a one-shot bounded warm-cache refresh. In the final rebuilt app, PID `46521`, the click-loop proxy peaked at `POWER 7.9`, dropped to `1.1` on the next sample after the loop, and reached `0.0` on the following sample. The click automation was interrupted during execution, so this is supporting evidence from the partial/final loop rather than a full Activity Monitor pass.
- These remain supporting evidence only, not an Activity Monitor pass.

Provider-write proxy:

- With the final PID `102`, the menu was opened while this Codex session generated natural local session writes from read-only commands (`git status --short`, `rg`, and `date`).
- `top -l 45 -s 1 -pid 102 -stats pid,command,power,cpu,time,threads,wq,csw` showed one `POWER 36.4` sample, then `4.0`, then `0.0`; no proxy sample reached the Scenario C failure threshold of `>=50`.
- This remains supporting evidence only, not an Activity Monitor pass.

## Activity Monitor Sampling Evidence

Activity Monitor accessibility sampling successfully read the Energy pane row:

```text
Agents Widget|0.0|91.70|No|No|ethanhuang
```

Interpreted visible columns:

- App Name: `Agents Widget`
- Energy Impact: `0.0`
- 12 hr Power: `91.70` (polluted by earlier development/debug launches)
- App Nap: `No`
- Preventing Sleep: `No`

Partial Scenario A evidence:

- First automated hidden-idle run produced 18 valid 30-second samples from `17:01:15-0700` through `17:09:57-0700`; all valid Energy Impact values were `0.0`.
- Clean restart produced 5 valid 60-second samples from `17:49:50-0700` through `17:53:52-0700`; all valid Energy Impact values were `0.0`.
- Activity Monitor then reported `Can't get window 1 of process "Activity Monitor". Invalid index. (-1719)`, preventing a complete uninterrupted 10-minute automated pass.

Final Scenario A product-facing pass:

```text
2026-05-04 19:54:24 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.17 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.12 | Idle Wake Ups missing value
2026-05-04 19:55:24 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.17 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.12 | Idle Wake Ups missing value
2026-05-04 19:56:24 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 19:57:25 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 19:58:25 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 19:59:25 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 20:00:26 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 20:01:26 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 20:02:26 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 20:03:26 PDT | Agents Widget | Energy Impact 0.0 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.27 | Idle Wake Ups 0
2026-05-04 20:04:27 PDT | Agents Widget | Energy Impact 0.1 | 12 hr Power 92.18 | App Nap No | Preventing Sleep No | User ethanhuang | CPU Time 1.96 | Idle Wake Ups 0
```

Average Energy Impact over the uninterrupted 10-minute span: `(0.1 / 11) = 0.0091`, which passes the `<= 0.1` target. CPU Time was stable from sample 3 through sample 10, then increased on the final sample while Energy Impact remained within target. Idle Wake Ups stayed `0` once the column reported a numeric value.

Crash discovery and fix:

- Opening Agents Widget via accessibility initially caused `agents-widget` crash reports at `16:50:19` and `16:58:31`.
- Crash report `agents-widget-2026-05-04-165831.ips` pointed to `AgentMonitor.updateProcessExitWatchers(for:)`, where a `DispatchSourceProcess` handler installed from `@MainActor` code ran on a utility queue and hit Swift's executor assertion.
- The process-exit source now uses `.main` and no empty cancel handler. `swift test` passes after the fix, menu open/close accessibility survived, and no newer `agents-widget` crash report appeared after `16:58:31`.

## Remaining Manual Gates

`powermetrics --show-process-energy` is the closest CLI substitute for Activity Monitor Energy Impact, but macOS returned:

```text
powermetrics must be invoked as the superuser
```

The non-interactive sudo attempt returned:

```text
sudo: a password is required
```

Continuation audit:

- `pgrep -fl agents-widget` confirmed the packaged app still running as PID `46665`.
- `top -l 1 -pid 46665 -stats pid,command,cpu,time,threads,wq,csw` reported `agents-widget` at `0.0` CPU with `00:00.74` CPU time.
- `ps -o pid,comm,cputime,time,wq,state -p 46665` reported PID `46665`, CPU time `0:00.75`, work queues `1`, state `S`.
- `pmset -g assertions` showed no Agents Widget sleep-prevention assertion; the only `PreventUserIdleSystemSleep` assertion was owned by `caffeinate`.
- `launchctl procinfo 46665` cannot be used as a non-root substitute because macOS returned `This subcommand requires root privileges: procinfo`.
- `man top` exposes CPU/process stats, but no Activity Monitor-equivalent `Energy Impact`, `12 hr Power`, or `Idle Wake Ups` field.
- `osascript` could launch Activity Monitor, but `System Events` reported no accessible windows. `reopen` still returned an empty window list, and the process reported `visible:false`.
- A final `set visible to true` / `activate` recovery attempt hung; the hung `osascript` process was terminated with `kill -TERM 91483`.
- A later keyboard-shortcut recovery attempt using Activity Monitor's standard `Command-1` window shortcut returned `false, false,` for `{frontmost, visible, name of windows}`, confirming no visible/accessibility window was restored.
- A clean Activity Monitor quit/relaunch and a LaunchServices `open -a "Activity Monitor"` launch still returned `false, false,` for `{frontmost, visible, name of windows}`.
- Setting `visible` directly on the Activity Monitor accessibility process changed the process flag to `true`, but `activate` still returned `false, true,` with an empty window list.
- Read-only preference inspection showed `OpenMainWindow = 1`, `SelectedTab = 2`, and `NSWindow Frame main window = "456 114 1014 695 0 0 1512 949 "`, so the stored main window frame is on-screen and the Energy tab is already selected.
- `/Users/ethanhuang/Library/Saved Application State/com.apple.ActivityMonitor.savedState` does not exist, so there is no Activity Monitor saved-state directory to remove.
- `open -F -a "Activity Monitor"` and `open -F -n -a "Activity Monitor"` also produced windowless Activity Monitor processes. The extra instance from `open -F -n` was terminated with `kill -TERM 67628`; one windowless Activity Monitor process remained.
- Activity Monitor's menu bar remained accessible and exposed `Apple, Activity Monitor, File, Edit, View, Window, Help`.
- The Window menu contained `Activity Monitor`, `Bring All to Front`, and `Activity Monitor (Applications in last 12 hours)`, but clicking each of those items still returned `false, true,` for `{frontmost, visible, name of windows}` with no accessible window.
- A final direct executable launch with a temporary HOME (`/private/tmp/agents-widget-activity-monitor-home`) did not create a second Activity Monitor process or restore a window. Accessibility still reported PID `18812`, `frontmost:false`, `visible:true`, and an empty window list. The temporary HOME contained only empty directories and was removed.
- A later clean quit successfully removed the stuck Activity Monitor process. Relaunching with `open -a "Activity Monitor"` started PID `67465`, but Accessibility still returned `false, true,` with an empty window list.
- Current preferences still show `OpenMainWindow = 1`, `SelectedTab = 2`, and an on-screen main window frame (`456 114 1014 695 0 0 1512 949`). No matching Activity Monitor saved-state directory exists under `~/Library/Saved Application State`.
- `tell application "Activity Monitor" to reopen` still returned `false, true,` with no windows. `tell application "Activity Monitor" to make new document` hung and the hung `osascript` PID `7999` was terminated with `kill -TERM 7999`.
- A direct visual fallback using `screencapture -x /private/tmp/agents-widget-activity-monitor-screen.png` failed with `could not create image from display`, so this agent cannot visually confirm whether Activity Monitor is present but inaccessible.
- A reversible preference reset was attempted after exporting `com.apple.ActivityMonitor` to `/private/tmp/com.apple.ActivityMonitor.agents-widget-backup.plist`. Resetting the domain and relaunching still returned `false, true,` with no windows. The backup was restored with `defaults import`, `OpenMainWindow` again read as `1`, Activity Monitor relaunched as PID `31121`, and the temporary backup file was removed.
- CoreGraphics window enumeration found a real Activity Monitor layer-0 window at `X = 486`, `Y = 204`, `Width = 913`, `Height = 627`, while Accessibility still reported no windows. A ScreenCaptureKit fallback failed with `SCStreamErrorDomain Code=-3801` and `The user declined TCCs for application, window, display capture`, so this agent cannot capture/OCR the visible window.
- Window-specific `screencapture -l 146051` failed with `could not create image from window`. Calling the legacy `CGWindowListCreateImage` symbol directly returned `nil`.
- Keyboard/focus recovery also failed: AppleScript `activate` left `Terminal` frontmost, coordinate click returned OSStatus `-25200`, a direct CoreGraphics click did not change frontmost app, and AppKit activation returned `true` but reported `loginwindow` as frontmost.
- Direct `AXUIElement` inspection of Activity Monitor exposed attributes including `AXWindows`, `AXMainWindow`, and `AXFocusedWindow`, but those attributes resolved to self-referential `AXApplication` elements plus the menu bar rather than the process table. `AXEnhancedUserInterface` already read as enabled, and the table still was not exposed.
- Local `powermetrics --help` confirms `--show-process-energy` is the per-process energy impact sampler and implicitly enables process CPU, wake, QoS, IO, GPU, network, and IPC statistics. The local help/man output exposes no non-root or PID-specific bypass, and `/usr/bin/powermetrics` is root-owned. Earlier direct and `sudo -n` attempts failed because superuser access/password is required.

All required Activity Monitor scenarios have product-facing pass evidence in this file. Admin `powermetrics` remains an optional alternate capture path, not a current blocker.

## Manual Activity Monitor Capture Worksheet

Current final app under test: packaged `Agents Widget.app`, process `agents-widget`, PID `64031` at the last audit.

Before recording values:

1. Open Activity Monitor's Energy tab.
2. Use the search/filter field for `Agents Widget`.
3. Ensure these columns are visible: `Energy Impact`, `12 hr Power`, `CPU Time`, `Idle Wake Ups`.
4. Record the visible `Agents Widget` row values and timestamps for each scenario below.

Scenario A - hidden idle:

- Keep the Agents Widget menu closed for 10 minutes.
- Record Energy Impact once per minute.
- Pass if Energy Impact is usually `0.0` and the 10-minute average is `<= 0.1`.

Scenario B - warm open/close:

- With the app already warm, open and close the Agents Widget menu 20 times.
- Record peak Energy Impact during the loop.
- Record how long it takes to settle below `2` after the final close.
- Pass if peak is `<= 20` and settle below `2` is within 3 seconds.

Scenario C - menu open with local agent writes:

- Leave the Agents Widget menu open while local Codex/OpenCode sessions write activity.
- Record peak Energy Impact and any sustained values.
- Pass if no random spike reaches `>= 50`.

Scenario D - manual deep refresh:

- Click the Agents Widget refresh button once.
- Record peak Energy Impact during refresh.
- Record how long it takes to settle below `2`.
- Pass if peak is `<= 50` and settle below `2` is within 10 seconds.

Manual results to append:

```text
Scenario A:
timestamps/values:
average:
pass/fail:

Scenario B:
peak:
settle time:
pass/fail:

Scenario C:
peak:
notes:
pass/fail:

Scenario D:
peak:
settle time:
pass/fail:
```

## Admin Powermetrics Capture Alternative

If manual Activity Monitor capture is not possible, `scripts/collect-powermetrics-energy.sh` can collect per-process energy-impact evidence with admin/root privileges.

The script records metadata and `powermetrics --show-process-energy --show-process-samp-norm --show-usage-summary` output under `build/m1_5-energy-evidence/`.

Example commands:

```bash
sudo scripts/collect-powermetrics-energy.sh scenario-a-hidden-idle 600 1000
sudo scripts/collect-powermetrics-energy.sh scenario-b-warm-open-close 90 1000
sudo scripts/collect-powermetrics-energy.sh scenario-c-provider-writes 120 1000
sudo scripts/collect-powermetrics-energy.sh scenario-d-manual-refresh 60 1000
```

The script was syntax/help checked. A non-root dry run exited with code `77` and printed the exact `sudo` command to rerun.

## Known Limitations

- Activity Monitor Energy Impact is still the product-facing pass/fail signal for M1.5.
- CLI profile and `top` output are supporting evidence only.
- Process discovery can require running outside the command sandbox because `/bin/ps` is denied inside this agent sandbox; the packaged app itself runs outside that sandbox.
- The reported `300+` Activity Monitor click spike was addressed in code and Scenario B was repeated with Activity Monitor evidence.
