import Foundation

public struct ProviderResult<Value>: Sendable where Value: Sendable {
    public var value: Value
    public var diagnostics: [String]

    public init(value: Value, diagnostics: [String] = []) {
        self.value = value
        self.diagnostics = diagnostics
    }
}
