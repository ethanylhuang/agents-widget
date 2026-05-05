import XCTest
@testable import AgentsWidgetCore

final class MenuBarRootViewTests: XCTestCase {
    func testFirstRefreshEmptyStateShowsRefreshing() {
        XCTAssertEqual(
            MenuBarRootView.emptyStateTitle(isRefreshing: true, lastRefreshAt: nil),
            "Refreshing..."
        )
    }

    func testCompletedEmptyStateShowsNoAgentsFound() {
        XCTAssertEqual(
            MenuBarRootView.emptyStateTitle(isRefreshing: false, lastRefreshAt: Date()),
            "No local agents found"
        )
    }

    func testActiveEmptyStateShowsNoOpenTerminalAgents() {
        XCTAssertEqual(
            MenuBarRootView.emptyStateTitle(filter: .activeTerminal, isRefreshing: false, lastRefreshAt: Date()),
            "No open Terminal agents"
        )
    }

    func testAttentionSummaryTakesPriorityOverActiveCount() {
        XCTAssertEqual(MenuBarRootView.statusSummary(attentionCount: 2, activeCount: 4), "2 need attention")
        XCTAssertEqual(MenuBarRootView.statusSummary(attentionCount: 0, activeCount: 4), "4 active")
        XCTAssertEqual(MenuBarRootView.statusSummary(attentionCount: 0, activeCount: 0), "Idle")
    }
}
