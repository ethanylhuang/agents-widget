import Foundation

public struct ProviderMetrics: Codable, Equatable, Sendable {
    public var bytesRead: Int64
    public var filesParsed: Int
    public var sqliteQueries: Int
    public var processSyscalls: Int

    public init(
        bytesRead: Int64 = 0,
        filesParsed: Int = 0,
        sqliteQueries: Int = 0,
        processSyscalls: Int = 0
    ) {
        self.bytesRead = bytesRead
        self.filesParsed = filesParsed
        self.sqliteQueries = sqliteQueries
        self.processSyscalls = processSyscalls
    }

    public static var zero: ProviderMetrics {
        ProviderMetrics()
    }

    public mutating func merge(_ other: ProviderMetrics) {
        bytesRead += other.bytesRead
        filesParsed += other.filesParsed
        sqliteQueries += other.sqliteQueries
        processSyscalls += other.processSyscalls
    }

    public static func + (lhs: ProviderMetrics, rhs: ProviderMetrics) -> ProviderMetrics {
        var metrics = lhs
        metrics.merge(rhs)
        return metrics
    }
}

public struct ProviderResult<Value>: Sendable where Value: Sendable {
    public var value: Value
    public var diagnostics: [String]
    public var metrics: ProviderMetrics

    public init(value: Value, diagnostics: [String] = [], metrics: ProviderMetrics = .zero) {
        self.value = value
        self.diagnostics = diagnostics
        self.metrics = metrics
    }
}
