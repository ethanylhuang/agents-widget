import XCTest
@testable import AgentsWidgetCore

final class FormatterTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(AgentFormatters.formatDuration(724), "12m 04s")
        XCTAssertEqual(AgentFormatters.formatDuration(8_040), "2h 14m")
        XCTAssertEqual(AgentFormatters.formatDuration(nil), "Unknown")
    }

    func testTokenFormatting() {
        XCTAssertEqual(AgentFormatters.formatTokenCount(834), "834 tok")
        XCTAssertEqual(AgentFormatters.formatTokenCount(832_600), "832.6k tok")
        XCTAssertEqual(AgentFormatters.formatTokenCount(nil), "Tokens unavailable")
    }

    func testCompactDurationFormatting() {
        XCTAssertEqual(AgentFormatters.formatCompactDuration(724), "12m")
        XCTAssertEqual(AgentFormatters.formatCompactDuration(8_040), "2h 14m")
        XCTAssertEqual(AgentFormatters.formatCompactDuration(266_400), "3d 02h")
        XCTAssertEqual(AgentFormatters.formatCompactDuration(nil), "Unknown")
    }

    func testCompactTokenFormatting() {
        XCTAssertEqual(AgentFormatters.formatCompactTokenCount(834), "834 tok")
        XCTAssertEqual(AgentFormatters.formatCompactTokenCount(832_600), "832.6k tok")
        XCTAssertEqual(AgentFormatters.formatCompactTokenCount(1_200_000), "1.2M tok")
        XCTAssertEqual(AgentFormatters.formatCompactTokenCount(nil), "Tokens unavailable")
    }

    func testCostFormatting() {
        XCTAssertEqual(AgentFormatters.formatCostUSD(Decimal(string: "0.042")), "$0.042")
        XCTAssertEqual(AgentFormatters.formatCostUSD(Decimal(string: "3.12")), "$3.12")
        XCTAssertEqual(AgentFormatters.formatCostUSD(nil), "Cost unavailable")
    }

    func testPathBasenameFormatting() {
        XCTAssertEqual(AgentFormatters.formatPathBasename("/Users/ethanhuang/agents-widget"), "agents-widget")
        XCTAssertEqual(AgentFormatters.formatPathBasename(nil), "Unknown path")
    }

    func testM2DisplayFormatting() {
        XCTAssertEqual(AgentFormatters.formatProjectTitle("/Users/ethanhuang/agents-widget"), "agents-widget")
        XCTAssertEqual(AgentFormatters.formatProjectTitle(nil), "Unknown project")
        XCTAssertEqual(
            AgentFormatters.formatSessionSubtitle(provider: .opencode, title: "Running project demo"),
            "OpenCode session: Running project demo"
        )
        XCTAssertEqual(
            AgentFormatters.formatSessionSubtitle(provider: .codex, title: " "),
            "Codex session unavailable"
        )
    }
}
