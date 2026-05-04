import Foundation

public enum Diagnostics {
    public static func codex(_ message: String) -> String {
        "Codex: \(message)"
    }

    public static func openCode(_ message: String) -> String {
        "OpenCode: \(message)"
    }

    public static func process(_ message: String) -> String {
        "Process: \(message)"
    }

    public static func terminal(_ message: String) -> String {
        "Terminal: \(message)"
    }

    public static let tokensUnavailable = "Tokens unavailable"
    public static let costUnavailable = "Cost unavailable"
    public static let unknownTerminal = "Unknown terminal"
    public static let openCodeDBBusy = "OpenCode DB busy"
}
