import XCTest
@testable import AgentsWidgetCore

final class AgentRowViewTests: XCTestCase {
    func testDisplayModelExcludesRemovedRowDetails() {
        let agent = AgentSummary(
            id: "agent-1",
            provider: .codex,
            title: "Focused agent list",
            cwd: "/Users/ethanhuang/agents-widget",
            tty: "/dev/ttys004",
            status: .idle,
            runtimeSeconds: 8_040,
            idleSeconds: 300,
            tokenUsage: TokenUsage(totalTokens: 832_600),
            costUSD: Decimal(string: "3.12"),
            activeTool: ToolCallSummary(name: "bash", status: "running")
        )

        let model = AgentRowDisplayModel(agent: agent)
        let visibleText = [
            model.sessionSubtitle,
        ].compactMap { $0 } + [
            model.projectTitle,
            model.runtimeText,
            model.tokenText,
            model.statusText
        ]

        XCTAssertEqual(model.projectTitle, "agents-widget")
        XCTAssertEqual(model.sessionSubtitle, "Codex session: Focused agent list")
        XCTAssertEqual(model.runtimeText, "2h 14m")
        XCTAssertEqual(model.tokenText, "832.6k tok")
        XCTAssertFalse(visibleText.joined(separator: " ").contains("/dev/ttys004"))
        XCTAssertFalse(visibleText.joined(separator: " ").contains("bash"))
        XCTAssertFalse(visibleText.joined(separator: " ").contains("$3.12"))
        XCTAssertFalse(visibleText.joined(separator: " ").localizedCaseInsensitiveContains("idle 5m"))
    }

    func testDisplayModelSuppressesRedundantProjectSubtitle() {
        let agent = AgentSummary(
            id: "agent-1",
            provider: .codex,
            title: "Codex - agents-widget",
            cwd: "/Users/ethanhuang/agents-widget",
            status: .running,
            runtimeSeconds: 120,
            tokenUsage: TokenUsage(totalTokens: 1_200)
        )

        let model = AgentRowDisplayModel(agent: agent)

        XCTAssertEqual(model.projectTitle, "agents-widget")
        XCTAssertNil(model.sessionSubtitle)
    }
}
