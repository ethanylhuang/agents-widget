import SwiftUI

public struct AgentRowView: View {
    let agent: AgentSummary
    let action: () -> Void
    @State private var isHovering = false

    public init(agent: AgentSummary, action: @escaping () -> Void) {
        self.agent = agent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: providerSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(providerColor)
                        .frame(width: 18, height: 18)
                }
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(agent.provider.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(providerColor)
                        Text(agent.status.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }

                    Text(agent.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(agent.cwd ?? "")

                    Text(metricsLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var metadataLine: String {
        let path = AgentFormatters.formatPathBasename(agent.cwd)
        let runtime = AgentFormatters.formatDuration(agent.runtimeSeconds)
        let idle = AgentFormatters.formatDuration(agent.idleSeconds)
        let terminal = agent.tty ?? Diagnostics.unknownTerminal
        return "\(path) - runtime \(runtime) - idle \(idle) - \(terminal)"
    }

    private var metricsLine: String {
        var parts: [String] = [
            AgentFormatters.formatTokenCount(agent.tokenUsage?.totalTokens),
            AgentFormatters.formatCostUSD(agent.costUSD)
        ]
        if let activeTool = agent.activeTool {
            parts.append(AgentFormatters.formatTool(activeTool))
        } else {
            parts.append("No active tool")
        }
        return parts.joined(separator: " - ")
    }

    private var providerSymbol: String {
        switch agent.provider {
        case .codex:
            "sparkles"
        case .opencode:
            "chevron.left.forwardslash.chevron.right"
        }
    }

    private var providerColor: Color {
        switch agent.provider {
        case .codex:
            .blue
        case .opencode:
            .orange
        }
    }

    private var statusColor: Color {
        switch agent.status {
        case .running:
            .green
        case .idle:
            .yellow
        case .stuck, .error:
            .red
        case .complete, .unknown:
            .secondary
        }
    }
}
