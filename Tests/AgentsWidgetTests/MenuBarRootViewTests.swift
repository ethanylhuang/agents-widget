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
}
