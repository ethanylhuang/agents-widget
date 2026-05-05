import Foundation

public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case opencode

    public var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .opencode:
            "OpenCode"
        }
    }
}

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case running
    case idle
    case stuck
    case complete
    case error
    case unknown
}

public enum AgentListFilter: String, Codable, CaseIterable, Sendable {
    case activeTerminal
    case allTasks
}

public enum AgentAttentionReason: String, Codable, CaseIterable, Sendable {
    case inputNeeded
    case stuck
    case error
    case completed
}

public enum AgentOpenActivityKind: String, Codable, Sendable {
    case modelTurn
    case toolCall
}

public enum ProviderTerminalState: String, Codable, Sendable {
    case running
    case complete
    case error
    case unknown
}

public struct AgentStatusEvidence: Codable, Equatable, Sendable {
    public var providerTerminalState: ProviderTerminalState
    public var openActivityKind: AgentOpenActivityKind?
    public var openActivityStartedAt: Date?
    public var openActivityUpdatedAt: Date?
    public var lastAssistantOrToolActivityAt: Date?
    public var lastUserInputAt: Date?
    public var evidenceObservedAt: Date?

    public init(
        providerTerminalState: ProviderTerminalState = .unknown,
        openActivityKind: AgentOpenActivityKind? = nil,
        openActivityStartedAt: Date? = nil,
        openActivityUpdatedAt: Date? = nil,
        lastAssistantOrToolActivityAt: Date? = nil,
        lastUserInputAt: Date? = nil,
        evidenceObservedAt: Date? = nil
    ) {
        self.providerTerminalState = providerTerminalState
        self.openActivityKind = openActivityKind
        self.openActivityStartedAt = openActivityStartedAt
        self.openActivityUpdatedAt = openActivityUpdatedAt
        self.lastAssistantOrToolActivityAt = lastAssistantOrToolActivityAt
        self.lastUserInputAt = lastUserInputAt
        self.evidenceObservedAt = evidenceObservedAt
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var cachedInputTokens: Int?
    public var outputTokens: Int?
    public var reasoningOutputTokens: Int?
    public var totalTokens: Int?

    public init(
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningOutputTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

public struct ToolCallSummary: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    public var status: String
    public var startedAt: Date?
    public var completedAt: Date?
    public var ageSeconds: TimeInterval?

    public init(
        id: String? = nil,
        name: String,
        status: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        ageSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.ageSeconds = ageSeconds
    }

    public var isIncomplete: Bool {
        completedAt == nil && status.lowercased() != "completed"
    }
}

public struct TerminalTarget: Codable, Equatable, Sendable {
    public var appName: String
    public var tty: String
    public var pid: Int32

    public init(appName: String = "Terminal", tty: String, pid: Int32) {
        self.appName = appName
        self.tty = tty
        self.pid = pid
    }
}

public struct AgentSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var provider: AgentProvider
    public var title: String
    public var cwd: String?
    public var pid: Int32?
    public var tty: String?
    public var status: AgentStatus
    public var startedAt: Date?
    public var lastActivityAt: Date?
    public var runtimeSeconds: TimeInterval?
    public var idleSeconds: TimeInterval?
    public var tokenUsage: TokenUsage?
    public var costUSD: Decimal?
    public var activeTool: ToolCallSummary?
    public var terminalTarget: TerminalTarget?
    public var attentionReasons: [AgentAttentionReason]
    public var statusEvidence: AgentStatusEvidence?
    public var diagnostics: [String]

    public init(
        id: String,
        provider: AgentProvider,
        title: String,
        cwd: String? = nil,
        pid: Int32? = nil,
        tty: String? = nil,
        status: AgentStatus = .unknown,
        startedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        runtimeSeconds: TimeInterval? = nil,
        idleSeconds: TimeInterval? = nil,
        tokenUsage: TokenUsage? = nil,
        costUSD: Decimal? = nil,
        activeTool: ToolCallSummary? = nil,
        terminalTarget: TerminalTarget? = nil,
        attentionReasons: [AgentAttentionReason] = [],
        statusEvidence: AgentStatusEvidence? = nil,
        diagnostics: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.cwd = cwd
        self.pid = pid
        self.tty = tty
        self.status = status
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.runtimeSeconds = runtimeSeconds
        self.idleSeconds = idleSeconds
        self.tokenUsage = tokenUsage
        self.costUSD = costUSD
        self.activeTool = activeTool
        self.terminalTarget = terminalTarget
        self.attentionReasons = attentionReasons
        self.statusEvidence = statusEvidence
        self.diagnostics = diagnostics
    }

    public var isActionableTerminalJump: Bool {
        terminalTarget != nil
    }

    public var isTerminalBacked: Bool {
        terminalTarget != nil || (pid != nil && tty != nil)
    }

    public var needsAttention: Bool {
        !attentionReasons.isEmpty
    }
}

extension AgentSummary {
    func refreshedDynamicFields(now: Date) -> AgentSummary {
        var summary = self
        summary.runtimeSeconds = startedAt.map { max(0, now.timeIntervalSince($0)) }
        summary.idleSeconds = lastActivityAt.map { max(0, now.timeIntervalSince($0)) }
        if var tool = activeTool, tool.isIncomplete {
            tool.ageSeconds = tool.startedAt.map { max(0, now.timeIntervalSince($0)) }
            summary.activeTool = tool
        }
        return summary
    }
}
