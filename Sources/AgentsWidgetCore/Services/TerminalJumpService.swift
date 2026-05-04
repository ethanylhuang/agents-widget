import AppKit
import Foundation

public enum TerminalJumpResult: Equatable, Sendable {
    case focused
    case terminalActivatedOnly(String)
    case missingTTY
    case automationDenied(String)
    case failed(String)

    public var displayMessage: String? {
        switch self {
        case .focused:
            nil
        case .terminalActivatedOnly(let message), .automationDenied(let message), .failed(let message):
            message
        case .missingTTY:
            Diagnostics.unknownTerminal
        }
    }
}

public protocol TerminalJumping: Sendable {
    func jump(to target: TerminalTarget?) async -> TerminalJumpResult
}

public final class TerminalJumpService: TerminalJumping, @unchecked Sendable {
    public init() {}

    public func jump(to target: TerminalTarget?) async -> TerminalJumpResult {
        guard let target, let tty = Self.normalizedTTY(target.tty) else {
            return .missingTTY
        }

        let script = Self.appleScript(for: tty)
        do {
            let output = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script]
            )
            if output.contains("focused") {
                return .focused
            }
            let activated = await Self.activateTerminal()
            if activated {
                return .terminalActivatedOnly("Terminal activated, but no tab matched \(tty).")
            }
            return .failed("Terminal tab \(tty) was not found.")
        } catch {
            let message = error.localizedDescription
            let activated = await Self.activateTerminal()
            if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
                if activated {
                    return .automationDenied("Automation denied; Terminal was activated without selecting the tab.")
                }
                return .automationDenied("Automation denied and Terminal could not be activated.")
            }
            if activated {
                return .terminalActivatedOnly("Terminal activated; tab focusing failed: \(message)")
            }
            return .failed("Terminal focusing failed: \(message)")
        }
    }

    static func normalizedTTY(_ raw: String?) -> String? {
        ProcessSnapshotProvider.normalizedTTY(raw)
    }

    static func appleScript(for tty: String) -> String {
        let escapedTTY = tty.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(escapedTTY)" then
                set selected tab of w to t
                set index of w to 1
                return "focused"
              end if
            end repeat
          end repeat
        end tell
        return "not_found"
        """
    }

    @MainActor
    private static func activateTerminal() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier == "com.apple.Terminal" || app.localizedName == "Terminal"
        }
        guard let terminal = apps.first else {
            return false
        }
        return terminal.activate(options: [.activateAllWindows])
    }
}
