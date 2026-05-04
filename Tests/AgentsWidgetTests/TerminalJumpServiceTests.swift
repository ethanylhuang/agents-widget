import XCTest
@testable import AgentsWidgetCore

final class TerminalJumpServiceTests: XCTestCase {
    func testGeneratesScriptWithNormalizedTTY() {
        let tty = TerminalJumpService.normalizedTTY("s000")
        XCTAssertEqual(tty, "/dev/ttys000")

        let script = TerminalJumpService.appleScript(for: tty!)
        XCTAssertTrue(script.contains("tty of t is \"/dev/ttys000\""))
        XCTAssertTrue(script.contains("return \"focused\""))
    }

    func testMissingTTYResult() async {
        let result = await TerminalJumpService().jump(to: nil)
        XCTAssertEqual(result, .missingTTY)
    }
}
