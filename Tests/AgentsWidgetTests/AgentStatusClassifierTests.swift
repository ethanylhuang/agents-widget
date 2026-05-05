import XCTest
@testable import AgentsWidgetCore

final class AgentStatusClassifierTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testLiveMatchedProcessAloneIsIdleNotRunning() {
        let agent = terminalBackedAgent()

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .idle)
    }

    func testProcessOnlyUnmatchedRowIsUnknown() {
        let agent = terminalBackedAgent()

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: false, now: now)

        XCTAssertEqual(status, .unknown)
    }

    func testFreshAssistantOrToolActivityWithLiveProcessIsRunning() {
        var agent = terminalBackedAgent()
        agent.statusEvidence = AgentStatusEvidence(lastAssistantOrToolActivityAt: now.addingTimeInterval(-10))

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .running)
    }

    func testLiveTerminalBackedMatchedSessionWithoutFreshActivityIsIdle() {
        var agent = terminalBackedAgent()
        agent.statusEvidence = AgentStatusEvidence(lastAssistantOrToolActivityAt: now.addingTimeInterval(-60))

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .idle)
    }

    func testFreshIncompleteToolIsRunning() {
        var agent = terminalBackedAgent()
        agent.statusEvidence = AgentStatusEvidence(
            openActivityKind: .toolCall,
            openActivityStartedAt: now.addingTimeInterval(-20),
            openActivityUpdatedAt: now.addingTimeInterval(-10)
        )

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .running)
    }

    func testStaleIncompleteToolIsStuck() {
        var agent = terminalBackedAgent()
        agent.statusEvidence = AgentStatusEvidence(
            openActivityKind: .toolCall,
            openActivityStartedAt: now.addingTimeInterval(-120),
            openActivityUpdatedAt: now.addingTimeInterval(-120)
        )

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .stuck)
    }

    func testStaleProviderErrorDoesNotOverrideNewerLiveActivity() {
        var agent = terminalBackedAgent(status: .error)
        agent.statusEvidence = AgentStatusEvidence(
            providerTerminalState: .error,
            lastAssistantOrToolActivityAt: now.addingTimeInterval(-2)
        )

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .running)
    }

    func testExplicitCompleteAndErrorWithoutLiveProcessRemainFinal() {
        let complete = terminalBackedAgent(status: .complete, providerTerminalState: .complete)
        let error = terminalBackedAgent(status: .error, providerTerminalState: .error)
        let classifier = AgentStatusClassifier()

        XCTAssertEqual(classifier.classify(complete, hasLiveProcess: false, hasMatchedSession: true, now: now), .complete)
        XCTAssertEqual(classifier.classify(error, hasLiveProcess: false, hasMatchedSession: true, now: now), .error)
    }

    func testRecentUserInputFallsThroughToUnknownDuringIdleGrace() {
        var agent = terminalBackedAgent()
        agent.statusEvidence = AgentStatusEvidence(lastUserInputAt: now.addingTimeInterval(-2))

        let status = AgentStatusClassifier().classify(agent, hasLiveProcess: true, hasMatchedSession: true, now: now)

        XCTAssertEqual(status, .unknown)
    }

    private func terminalBackedAgent(
        status: AgentStatus = .unknown,
        providerTerminalState: ProviderTerminalState = .unknown
    ) -> AgentSummary {
        AgentSummary(
            id: UUID().uuidString,
            provider: .codex,
            title: "Task",
            cwd: "/tmp/agents-widget",
            pid: 123,
            tty: "/dev/ttys001",
            status: status,
            startedAt: now.addingTimeInterval(-600),
            lastActivityAt: now.addingTimeInterval(-120),
            terminalTarget: TerminalTarget(tty: "/dev/ttys001", pid: 123),
            statusEvidence: AgentStatusEvidence(providerTerminalState: providerTerminalState)
        )
    }
}
