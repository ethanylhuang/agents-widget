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

    func testCostFormatting() {
        XCTAssertEqual(AgentFormatters.formatCostUSD(Decimal(string: "0.042")), "$0.042")
        XCTAssertEqual(AgentFormatters.formatCostUSD(Decimal(string: "3.12")), "$3.12")
        XCTAssertEqual(AgentFormatters.formatCostUSD(nil), "Cost unavailable")
    }

    func testPathBasenameFormatting() {
        XCTAssertEqual(AgentFormatters.formatPathBasename("/Users/ethanhuang/agents-widget"), "agents-widget")
        XCTAssertEqual(AgentFormatters.formatPathBasename(nil), "Unknown path")
    }
}
