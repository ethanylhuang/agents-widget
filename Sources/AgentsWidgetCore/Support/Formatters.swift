import Foundation

public enum AgentFormatters {
    public static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return "Unknown"
        }
        let total = Int(seconds.rounded(.down))
        if total < 3_600 {
            return String(format: "%dm %02ds", total / 60, total % 60)
        }
        return String(format: "%dh %02dm", total / 3_600, (total % 3_600) / 60)
    }

    public static func formatTokenCount(_ tokens: Int?) -> String {
        guard let tokens else {
            return Diagnostics.tokensUnavailable
        }
        if tokens < 1_000 {
            return "\(tokens) tok"
        }
        return String(format: "%.1fk tok", Double(tokens) / 1_000.0)
    }

    public static func formatCompactDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return "Unknown"
        }
        let total = Int(seconds.rounded(.down))
        if total < 3_600 {
            return "\(total / 60)m"
        }
        if total < 86_400 {
            return String(format: "%dh %02dm", total / 3_600, (total % 3_600) / 60)
        }
        return String(format: "%dd %02dh", total / 86_400, (total % 86_400) / 3_600)
    }

    public static func formatCompactTokenCount(_ tokens: Int?) -> String {
        guard let tokens else {
            return Diagnostics.tokensUnavailable
        }
        if tokens < 1_000 {
            return "\(tokens) tok"
        }
        if tokens < 1_000_000 {
            return String(format: "%.1fk tok", Double(tokens) / 1_000.0)
        }
        return String(format: "%.1fM tok", Double(tokens) / 1_000_000.0)
    }

    public static func formatCostUSD(_ cost: Decimal?) -> String {
        guard let cost else {
            return Diagnostics.costUnavailable
        }
        let number = NSDecimalNumber(decimal: cost)
        if number.compare(1) == .orderedAscending {
            return String(format: "$%.3f", number.doubleValue)
        }
        return String(format: "$%.2f", number.doubleValue)
    }

    public static func formatPathBasename(_ path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "Unknown path"
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    public static func formatProjectTitle(_ path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "Unknown project"
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }

    public static func formatSessionSubtitle(provider: AgentProvider, title: String?) -> String {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleanTitle, !cleanTitle.isEmpty else {
            return "\(provider.displayName) session unavailable"
        }
        return "\(provider.displayName) session: \(cleanTitle)"
    }

    public static func formatTool(_ tool: ToolCallSummary?) -> String {
        guard let tool else {
            return "No active tool"
        }
        let age = formatDuration(tool.ageSeconds)
        return "\(tool.name) \(age)"
    }
}
