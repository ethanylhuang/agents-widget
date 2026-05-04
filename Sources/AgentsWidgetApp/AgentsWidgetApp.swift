import AgentsWidgetCore
import Foundation
import SwiftUI

@main
struct AgentsWidgetApp: App {
    @StateObject private var monitor = AgentMonitor.live()
    @State private var didStartMonitor = false

    init() {
        if CommandLine.arguments.contains("--smoke-json") {
            SmokeProbe.run(attemptTerminalJump: CommandLine.arguments.contains("--smoke-terminal"))
            Foundation.exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("Agents Widget", systemImage: "terminal") {
            MenuBarRootView(monitor: monitor)
                .onAppear {
                    guard !didStartMonitor else {
                        return
                    }
                    didStartMonitor = true
                    monitor.start()
                }
        }
        .menuBarExtraStyle(.window)
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
