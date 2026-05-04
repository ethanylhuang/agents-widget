# M1 Verification Evidence

Date: 2026-05-04

## Commands Run

```bash
pwd
swift --version
xcodebuild -version
which codex
which opencode
sqlite3 /Users/ethanhuang/.local/share/opencode/opencode.db .tables
swift test
swift build -c debug --product agents-widget
scripts/build-app.sh
scripts/run-app.sh
.build/debug/agents-widget --smoke-json
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json
build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json --smoke-terminal
/bin/ps -axo pid=,ppid=,tty=,lstart=,command=
/usr/bin/log show --style compact --last 10m --predicate 'process == "agents-widget"'
pgrep -fl agents-widget
```

## Build And Test Evidence

- `swift --version`: Apple Swift 6.2.
- `xcodebuild -version`: Xcode 26.0.1.
- `swift test`: 17 XCTest cases passed with 0 failures.
- `swift build -c debug --product agents-widget`: debug product built successfully.
- `scripts/build-app.sh`: created `/Users/ethanhuang/agents-widget/build/Agents Widget.app`.

## Local Discovery Evidence

The packaged smoke probe reported:

- `codexSessionCount`: 50
- `openCodeSessionCount`: 49
- `processCount`: 7
- `mergedAgentCount`: 99
- `diagnostics`: empty

The first visible rows included:

- `Codex - agents-widget`, `running`, PID-backed, `/dev/ttys005`, tokens available, active tool `exec_command`.
- `Codex - opencode-grok-auth`, `idle`, PID-backed, `/dev/ttys004`, tokens available.
- `Codex - Arduino`, `idle`, PID-backed, `/dev/ttys006`, tokens available.
- `OpenCode` title `Running project demo`, `idle`, PID-backed, `/dev/ttys001`, provider cost available.

The process table independently showed live `codex`, `codex resume`, and `opencode` processes attached to Terminal TTYs.

## Terminal Jump Evidence

`build/Agents\ Widget.app/Contents/MacOS/agents-widget --smoke-json --smoke-terminal` returned:

```text
terminalJumpResult: focused
```

## Manual Smoke Evidence

`scripts/run-app.sh` launched the packaged app. `pgrep -fl agents-widget` then showed:

```text
78152 /Users/ethanhuang/agents-widget/build/Agents Widget.app/Contents/MacOS/agents-widget
```

Recent macOS logs showed `agents-widget` registering as `application.com.local.agents-widget`, `uiElement=1`, and creating `NSStatusItem` scenes. No crash entry appeared in the inspected log window after the fix.

## Fix From Smoke Testing

The first smoke probe hung because `ProcessRunner` waited for `/bin/ps` to exit before draining stdout. The large local process table filled the pipe, blocking refresh and making the menu-bar app appear crashed or empty. `ProcessRunner` now drains stdout/stderr concurrently while the child process runs.

## Remaining Limitations

- Terminal.app focusing depends on macOS Automation permission. The verified local run returned `focused`; denied permission should surface as a non-fatal diagnostic.
- Process-to-session matching remains heuristic when cwd cannot be read.
- Codex titles intentionally use safe cwd/session fallbacks instead of raw prompt text.
