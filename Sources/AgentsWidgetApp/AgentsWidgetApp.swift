import AgentsWidgetCore
import Darwin
import Foundation
import SwiftUI

@main
struct AgentsWidgetApp: App {
    @StateObject private var monitor: AgentMonitor

    init() {
        if CommandLine.arguments.contains("--profile-refresh") {
            ProfileProbe.run()
            Foundation.exit(0)
        }
        if CommandLine.arguments.contains("--smoke-json") {
            SmokeProbe.run(attemptTerminalJump: CommandLine.arguments.contains("--smoke-terminal"))
            Foundation.exit(0)
        }

        let liveMonitor = AgentMonitor.live()
        _monitor = StateObject(wrappedValue: liveMonitor)
        Task { @MainActor in
            liveMonitor.start()
            liveMonitor.warmCache()
        }
    }

    var body: some Scene {
        MenuBarExtra("Agents Widget", systemImage: "terminal") {
            MenuBarRootView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
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
        let merged = AgentMonitor.merge(processes: processes.value, sessions: codex.value + openCode.value, now: now)
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
                tty: agent.tty,
                hasTokens: agent.tokenUsage?.totalTokens != nil,
                hasCost: agent.costUSD != nil,
                activeTool: agent.activeTool?.name,
                hasTerminalTarget: agent.terminalTarget != nil
            )
        }
        let diagnostics = processes.diagnostics + codex.diagnostics + openCode.diagnostics
        let report = SmokeReport(
            codexSessionCount: codex.value.count,
            openCodeSessionCount: openCode.value.count,
            processCount: processes.value.count,
            mergedAgentCount: merged.count,
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
    var tty: String?
    var hasTokens: Bool
    var hasCost: Bool
    var activeTool: String?
    var hasTerminalTarget: Bool
}
