import Foundation

public struct AgentStatusClassifier: Sendable {
    public var freshActivityWindowSeconds: TimeInterval
    public var staleOpenActivitySeconds: TimeInterval
    public var idleGraceSeconds: TimeInterval

    public init(
        freshActivityWindowSeconds: TimeInterval = 30,
        staleOpenActivitySeconds: TimeInterval = 90,
        idleGraceSeconds: TimeInterval = 5
    ) {
        self.freshActivityWindowSeconds = freshActivityWindowSeconds
        self.staleOpenActivitySeconds = staleOpenActivitySeconds
        self.idleGraceSeconds = idleGraceSeconds
    }

    public func classify(
        _ agent: AgentSummary,
        hasLiveProcess: Bool,
        hasMatchedSession: Bool,
        now: Date
    ) -> AgentStatus {
        let evidence = normalizedEvidence(for: agent, now: now)

        guard hasLiveProcess else {
            switch evidence.providerTerminalState {
            case .error:
                return .error
            case .complete:
                return .complete
            case .running, .unknown:
                switch agent.status {
                case .error:
                    return .error
                case .complete:
                    return .complete
                case .running, .idle, .stuck, .unknown:
                    return .unknown
                }
            }
        }

        guard hasMatchedSession else {
            return .unknown
        }

        if evidence.openActivityKind != nil {
            let reference = evidence.openActivityUpdatedAt
                ?? evidence.openActivityStartedAt
                ?? evidence.lastAssistantOrToolActivityAt
                ?? agent.lastActivityAt
                ?? agent.startedAt
            if let reference, now.timeIntervalSince(reference) >= staleOpenActivitySeconds {
                return .stuck
            }
            return .running
        }

        if let activity = evidence.lastAssistantOrToolActivityAt,
           now.timeIntervalSince(activity) <= freshActivityWindowSeconds {
            return .running
        }

        if isWithinIdleGrace(agent: agent, evidence: evidence, now: now) {
            return .unknown
        }

        if agent.isTerminalBacked {
            return .idle
        }

        return .unknown
    }

    private func normalizedEvidence(for agent: AgentSummary, now: Date) -> AgentStatusEvidence {
        var evidence = agent.statusEvidence ?? AgentStatusEvidence(providerTerminalState: terminalState(from: agent.status))

        if evidence.providerTerminalState == .unknown {
            evidence.providerTerminalState = terminalState(from: agent.status)
        }

        if evidence.openActivityKind == nil,
           let tool = agent.activeTool,
           tool.isIncomplete {
            evidence.openActivityKind = .toolCall
            evidence.openActivityStartedAt = tool.startedAt
            evidence.openActivityUpdatedAt = tool.completedAt ?? tool.startedAt
            evidence.lastAssistantOrToolActivityAt = evidence.lastAssistantOrToolActivityAt
                ?? tool.completedAt
                ?? tool.startedAt
            if evidence.openActivityStartedAt == nil,
               let age = tool.ageSeconds {
                let inferredStart = now.addingTimeInterval(-age)
                evidence.openActivityStartedAt = inferredStart
                evidence.openActivityUpdatedAt = inferredStart
            }
        }

        return evidence
    }

    private func terminalState(from status: AgentStatus) -> ProviderTerminalState {
        switch status {
        case .running:
            .running
        case .complete:
            .complete
        case .error:
            .error
        case .idle, .stuck, .unknown:
            .unknown
        }
    }

    private func isWithinIdleGrace(agent: AgentSummary, evidence: AgentStatusEvidence, now: Date) -> Bool {
        let reference = [evidence.lastUserInputAt, agent.startedAt].compactMap { $0 }.max()
        guard let reference else {
            return false
        }
        return now.timeIntervalSince(reference) < idleGraceSeconds
    }
}
