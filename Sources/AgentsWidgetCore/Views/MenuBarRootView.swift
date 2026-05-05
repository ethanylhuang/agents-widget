import SwiftUI

public struct MenuBarRootView: View {
    private static let visibleAgentLimit = 12

    @ObservedObject private var monitor: AgentMonitor
    private let terminalJumpService: any TerminalJumping
    @State private var jumpDiagnostic: String?
    @State private var selectedFilter: AgentListFilter = .activeTerminal

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
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            monitor.setMenuVisible(true)
        }
        .onDisappear {
            monitor.setMenuVisible(false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            }

            Picker("Filter", selection: $selectedFilter) {
                Text("Active").tag(AgentListFilter.activeTerminal)
                Text("All").tag(AgentListFilter.allTasks)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var content: some View {
        let visibleAgents = AgentMonitor.filteredAgents(monitor.agents, filter: selectedFilter)
        return Group {
            if visibleAgents.isEmpty {
                VStack(spacing: 6) {
                    Text(Self.emptyStateTitle(
                        filter: selectedFilter,
                        isRefreshing: monitor.isRefreshing,
                        lastRefreshAt: monitor.lastRefreshAt
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleAgents.prefix(Self.visibleAgentLimit))) { agent in
                            AgentRowView(agent: agent) {
                                Task {
                                    let result = await terminalJumpService.jump(to: agent.terminalTarget)
                                    jumpDiagnostic = result.displayMessage
                                }
                            }
                            Divider()
                        }
                        if visibleAgents.count > Self.visibleAgentLimit {
                            Text("\(visibleAgents.count - Self.visibleAgentLimit) more agents")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                    }
                }
                .frame(maxHeight: 404)
            }
        }
    }

    nonisolated static func emptyStateTitle(
        filter: AgentListFilter = .allTasks,
        isRefreshing: Bool,
        lastRefreshAt: Date?
    ) -> String {
        if isRefreshing && lastRefreshAt == nil {
            return "Refreshing..."
        }
        if filter == .activeTerminal {
            return "No open Terminal agents"
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

    private var statusSummary: String {
        Self.statusSummary(
            attentionCount: monitor.attentionCount,
            activeCount: AgentMonitor.filteredAgents(monitor.agents, filter: .activeTerminal).count
        )
    }

    nonisolated static func statusSummary(attentionCount: Int, activeCount: Int) -> String {
        if attentionCount > 0 {
            return "\(attentionCount) need attention"
        }
        if activeCount > 0 {
            return "\(activeCount) active"
        }
        return "Idle"
    }
}
