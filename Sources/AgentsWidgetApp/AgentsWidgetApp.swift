import AgentsWidgetCore
import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

@main
struct AgentsWidgetApp: App {
    @NSApplicationDelegateAdaptor(AgentsWidgetAppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--profile-refresh") {
            ProfileProbe.run()
            Foundation.exit(0)
        }
        if CommandLine.arguments.contains("--smoke-json") {
            SmokeProbe.run(attemptTerminalJump: CommandLine.arguments.contains("--smoke-terminal"))
            Foundation.exit(0)
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AgentsWidgetAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var monitor: AgentMonitor?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = AgentMonitor.live()
        self.monitor = monitor

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let hostingController = NSHostingController(rootView: MenuBarRootView(monitor: monitor))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        self.popover = popover

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        monitor.$attentionCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        updateStatusItem()
        monitor.start()
        monitor.warmCache()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func togglePopover(from sender: NSStatusBarButton) {
        guard let popover else {
            return
        }
        if popover.isShown {
            popover.performClose(sender)
            monitor?.setMenuVisible(false)
        } else {
            monitor?.setMenuVisible(true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApplication.shared.activate()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        monitor?.setMenuVisible(false)
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        popover?.performClose(sender)
        monitor?.setMenuVisible(false)
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }
        button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Agents")
        button.imagePosition = .imageLeft
        button.title = badgeTitle
        button.toolTip = "Agents"
    }

    private var badgeTitle: String {
        guard let attentionCount = monitor?.attentionCount, attentionCount > 0 else {
            return ""
        }
        return attentionCount > 9 ? "9+" : "\(attentionCount)"
    }
}

private enum ProfileProbe {
    static func run() {
        let processProvider = ProcessSnapshotProvider()
        let codexStore = CodexSessionStore()
        let openCodeStore = OpenCodeSessionStore()
        let cold = refreshSnapshot(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            reason: .menuOpen
        )
        let warmSnapshots = (0..<20).map { _ in
            refreshSnapshot(
                processProvider: processProvider,
                codexStore: codexStore,
                openCodeStore: openCodeStore,
                reason: .menuOpen
            )
        }
        let warm = warmSnapshots.first ?? cold
        let manualDeep = refreshSnapshot(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            mode: .deep,
            reason: .manual
        )
        let report = ProfileReport(
            profile: warm.profile,
            coldProfile: cold.profile,
            manualDeepProfile: manualDeep.profile,
            warmLoop: ProfileLoopSummary(snapshots: warmSnapshots),
            codexSessionCount: warm.codexSessionCount,
            openCodeSessionCount: warm.openCodeSessionCount,
            processCount: warm.processCount,
            mergedAgentCount: warm.mergedAgentCount,
            diagnostics: warm.diagnostics
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print("{\"error\":\"profile report encoding failed\"}")
        }
    }

    private static func refreshSnapshot(
        processProvider: ProcessSnapshotProvider,
        codexStore: CodexSessionStore,
        openCodeStore: OpenCodeSessionStore,
        mode: SessionRefreshMode = .bounded,
        reason: AgentRefreshReason
    ) -> ProfileSnapshot {
        let now = Date()
        let startedAt = Date()
        let startedCPU = currentCPUTime()
        let processes = processProvider.snapshots()
        let codex = codexStore.summaries(now: now, mode: mode)
        let openCode = openCodeStore.summaries(now: now, mode: mode)
        let merged = AgentMonitor.merge(processes: processes.value, sessions: codex.value + openCode.value, now: now)
        var metrics = processes.metrics
        metrics.merge(codex.metrics)
        metrics.merge(openCode.metrics)
        let duration = Date().timeIntervalSince(startedAt)
        let profile = RefreshProfile(
            reason: reason,
            wallTimeSeconds: duration,
            cpuTimeSeconds: max(0, currentCPUTime() - startedCPU),
            metrics: metrics
        )

        return ProfileSnapshot(
            profile: profile,
            codexSessionCount: codex.value.count,
            openCodeSessionCount: openCode.value.count,
            processCount: processes.value.count,
            mergedAgentCount: merged.count,
            diagnostics: processes.diagnostics + codex.diagnostics + openCode.diagnostics
        )
    }

    private static func currentCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return 0
        }
        let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}

private enum SmokeProbe {
    static func run(attemptTerminalJump: Bool) {
        let now = Date()
        let processes = ProcessSnapshotProvider().snapshots()
        let codex = CodexSessionStore().summaries(now: now)
        let openCode = OpenCodeSessionStore().summaries(now: now)
        let merged = AgentMonitor.sortedAgents(AgentMonitor.applyAttention(
            to: AgentMonitor.merge(processes: processes.value, sessions: codex.value + openCode.value, now: now),
            previousStatuses: [:],
            previousTerminalBackedIDs: []
        ))
        var terminalJumpResult: String?

        if attemptTerminalJump {
            let target = merged.first { $0.terminalTarget != nil }?.terminalTarget
            terminalJumpResult = smokeTerminalJump(to: target)
        }

        let smokeAgents = merged.prefix(10).map { agent in
            SmokeAgent(
                provider: agent.provider.rawValue,
                status: agent.status.rawValue,
                title: agent.title,
                hasPID: agent.pid != nil,
                hasTokens: agent.tokenUsage?.totalTokens != nil,
                hasTerminalTarget: agent.terminalTarget != nil,
                attentionReasons: agent.attentionReasons.map(\.rawValue),
                hasStatusEvidence: agent.statusEvidence != nil
            )
        }
        let diagnostics = processes.diagnostics + codex.diagnostics + openCode.diagnostics
        let report = SmokeReport(
            codexSessionCount: codex.value.count,
            openCodeSessionCount: openCode.value.count,
            processCount: processes.value.count,
            mergedAgentCount: merged.count,
            visibleActiveCount: AgentMonitor.filteredAgents(merged, filter: .activeTerminal).count,
            attentionCount: merged.filter(\.needsAttention).count,
            agents: smokeAgents,
            diagnostics: diagnostics,
            terminalJumpResult: terminalJumpResult
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print("{\"error\":\"smoke report encoding failed\"}")
        }
    }

    private static func smokeTerminalJump(to target: TerminalTarget?) -> String {
        guard let target, let tty = ProcessSnapshotProvider.normalizedTTY(target.tty) else {
            return "missingTTY"
        }
        let script = """
        tell application "Terminal"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected tab of w to t
                set index of w to 1
                return "focused"
              end if
            end repeat
          end repeat
        end tell
        return "not_found"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "failed: \(error.localizedDescription)"
        }
        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return outputText.contains("focused") ? "focused" : "terminalActivatedOnly: \(outputText.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if errorText.contains("-1743") || errorText.localizedCaseInsensitiveContains("not authorized") {
            return "automationDenied: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return "failed: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

private struct SmokeReport: Encodable {
    var codexSessionCount: Int
    var openCodeSessionCount: Int
    var processCount: Int
    var mergedAgentCount: Int
    var visibleActiveCount: Int
    var attentionCount: Int
    var agents: [SmokeAgent]
    var diagnostics: [String]
    var terminalJumpResult: String?
}

private struct ProfileReport: Encodable {
    var profile: RefreshProfile
    var coldProfile: RefreshProfile
    var manualDeepProfile: RefreshProfile
    var warmLoop: ProfileLoopSummary
    var codexSessionCount: Int
    var openCodeSessionCount: Int
    var processCount: Int
    var mergedAgentCount: Int
    var diagnostics: [String]
}

private struct ProfileSnapshot {
    var profile: RefreshProfile
    var codexSessionCount: Int
    var openCodeSessionCount: Int
    var processCount: Int
    var mergedAgentCount: Int
    var diagnostics: [String]
}

private struct ProfileLoopSummary: Encodable {
    var sampleCount: Int
    var maxWallTimeSeconds: TimeInterval
    var maxCPUTimeSeconds: TimeInterval
    var maxBytesRead: Int64
    var maxFilesParsed: Int
    var maxSQLiteQueries: Int
    var maxProcessSyscalls: Int

    init(snapshots: [ProfileSnapshot]) {
        sampleCount = snapshots.count
        maxWallTimeSeconds = snapshots.map(\.profile.wallTimeSeconds).max() ?? 0
        maxCPUTimeSeconds = snapshots.map(\.profile.cpuTimeSeconds).max() ?? 0
        maxBytesRead = snapshots.map(\.profile.bytesRead).max() ?? 0
        maxFilesParsed = snapshots.map(\.profile.filesParsed).max() ?? 0
        maxSQLiteQueries = snapshots.map(\.profile.sqliteQueries).max() ?? 0
        maxProcessSyscalls = snapshots.map(\.profile.processSyscalls).max() ?? 0
    }
}

private struct SmokeAgent: Encodable {
    var provider: String
    var status: String
    var title: String
    var hasPID: Bool
    var hasTokens: Bool
    var hasTerminalTarget: Bool
    var attentionReasons: [String]
    var hasStatusEvidence: Bool
}
