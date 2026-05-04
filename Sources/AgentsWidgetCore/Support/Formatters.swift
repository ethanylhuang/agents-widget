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

    public static func formatLastRefresh(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "Never refreshed"
        }
        let age = max(0, now.timeIntervalSince(date))
        if age < 60 {
            return "Updated \(Int(age))s ago"
        }
        return "Updated \(formatDuration(age)) ago"
    }

    public static func formatTool(_ tool: ToolCallSummary?) -> String {
        guard let tool else {
            return "No active tool"
        }
        let age = formatDuration(tool.ageSeconds)
        return "\(tool.name) \(age)"
    }
}
