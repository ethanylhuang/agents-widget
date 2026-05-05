import SwiftUI

struct AgentRowDisplayModel: Equatable {
    var projectTitle: String
    var sessionSubtitle: String?
    var runtimeText: String
    var tokenText: String
    var statusText: String

    init(agent: AgentSummary) {
        projectTitle = AgentFormatters.formatProjectTitle(agent.cwd)
        sessionSubtitle = Self.sessionSubtitle(
            provider: agent.provider,
            title: agent.title,
            projectTitle: projectTitle
        )
        runtimeText = AgentFormatters.formatCompactDuration(agent.runtimeSeconds)
        tokenText = AgentFormatters.formatCompactTokenCount(agent.tokenUsage?.totalTokens)
        statusText = agent.status.rawValue.capitalized
    }

    private static func sessionSubtitle(provider: AgentProvider, title: String, projectTitle: String) -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return nil
        }

        let normalizedProject = normalized(projectTitle)
        let normalizedTitle = normalized(cleanTitle)
        let providerPrefix = normalized(provider.displayName)
        let withoutProviderPrefix = normalizedTitle
            .replacingOccurrences(of: "\(providerPrefix) ", with: "")
            .replacingOccurrences(of: "\(provider.rawValue) ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedTitle == normalizedProject || withoutProviderPrefix == normalizedProject {
            return nil
        }
        if normalizedTitle.hasSuffix(" \(normalizedProject)") && normalizedTitle.hasPrefix(providerPrefix) {
            return nil
        }
        return AgentFormatters.formatSessionSubtitle(provider: provider, title: cleanTitle)
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
}

public struct AgentRowView: View {
    let agent: AgentSummary
    let action: () -> Void
    private var displayModel: AgentRowDisplayModel {
        AgentRowDisplayModel(agent: agent)
    }

    public init(agent: AgentSummary, action: @escaping () -> Void) {
        self.agent = agent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayModel.projectTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(displayModel.runtimeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let sessionSubtitle = displayModel.sessionSubtitle {
                            Text(sessionSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(displayModel.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(displayModel.tokenText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if displayModel.sessionSubtitle != nil {
                        Text(displayModel.statusText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
