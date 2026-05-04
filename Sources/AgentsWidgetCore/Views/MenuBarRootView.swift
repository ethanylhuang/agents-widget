import AppKit
import SwiftUI

public struct MenuBarRootView: View {
    @ObservedObject private var monitor: AgentMonitor
    private let terminalJumpService: any TerminalJumping
    @State private var jumpDiagnostic: String?

    public init(monitor: AgentMonitor, terminalJumpService: any TerminalJumping = TerminalJumpService()) {
        self.monitor = monitor
        self.terminalJumpService = terminalJumpService
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !monitor.diagnostics.isEmpty || jumpDiagnostic != nil {
                diagnosticsView
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
        .background(.regularMaterial)
        .onAppear {
            monitor.setMenuVisible(true)
            monitor.requestRefresh()
        }
        .onDisappear {
            monitor.setMenuVisible(false)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Agents")
                    .font(.headline)
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                monitor.requestRefresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var content: some View {
        Group {
            if monitor.agents.isEmpty {
                VStack(spacing: 6) {
                    Text(Self.emptyStateTitle(isRefreshing: monitor.isRefreshing, lastRefreshAt: monitor.lastRefreshAt))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(AgentFormatters.formatLastRefresh(monitor.lastRefreshAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.agents) { agent in
                            AgentRowView(agent: agent) {
                                Task {
                                    let result = await terminalJumpService.jump(to: agent.terminalTarget)
                                    jumpDiagnostic = result.displayMessage
                                }
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 404)
            }
        }
    }

    nonisolated static func emptyStateTitle(isRefreshing: Bool, lastRefreshAt: Date?) -> String {
        if isRefreshing && lastRefreshAt == nil {
            return "Refreshing..."
        }
        return "No local agents found"
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let jumpDiagnostic {
                diagnosticLine(jumpDiagnostic)
            }
            ForEach(Array(monitor.diagnostics.prefix(3)), id: \.self) { diagnostic in
                diagnosticLine(diagnostic)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var footer: some View {
        HStack {
            Text(AgentFormatters.formatLastRefresh(monitor.lastRefreshAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var statusSummary: String {
        let stuck = monitor.agents.filter { $0.status == .stuck }.count
        if stuck > 0 {
            return "\(stuck) stuck"
        }
        let running = monitor.agents.filter { $0.status == .running }.count
        if running > 0 {
            return "\(running) running"
        }
        let idle = monitor.agents.filter { $0.status == .idle }.count
        if idle > 0 {
            return "\(idle) idle"
        }
        return "Idle"
    }
}
