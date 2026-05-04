import Foundation

typealias JSONDictionary = [String: Any]

enum JSONHelpers {
    static func dictionary(from text: String) throws -> JSONDictionary {
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return object as? JSONDictionary ?? [:]
    }

    static func dictionary(_ dictionary: JSONDictionary, key: String) -> JSONDictionary? {
        dictionary[key] as? JSONDictionary
    }

    static func dictionary(_ dictionary: JSONDictionary, path: [String]) -> JSONDictionary? {
        var current: JSONDictionary? = dictionary
        for key in path {
            current = current?[key] as? JSONDictionary
        }
        return current
    }

    static func string(_ dictionary: JSONDictionary, keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    static func int(_ dictionary: JSONDictionary, keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String, let intValue = Int(value) {
                return intValue
            }
        }
        return nil
    }

    static func double(_ dictionary: JSONDictionary, keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[key] as? String, let doubleValue = Double(value) {
                return doubleValue
            }
        }
        return nil
    }

    static func decimal(_ dictionary: JSONDictionary, keys: [String]) -> Decimal? {
        for key in keys {
            if let value = dictionary[key] as? Decimal {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.decimalValue
            }
            if let value = dictionary[key] as? String, let decimal = Decimal(string: value) {
                return decimal
            }
        }
        return nil
    }

    static func bool(_ dictionary: JSONDictionary, keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let number = value as? NSNumber {
            return date(fromNumericTimestamp: number.doubleValue)
        }
        if let double = value as? Double {
            return date(fromNumericTimestamp: double)
        }
        if let int = value as? Int {
            return date(fromNumericTimestamp: Double(int))
        }
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        if let double = Double(string) {
            return date(fromNumericTimestamp: double)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nonFractional = ISO8601DateFormatter()
        return fractional.date(from: string) ?? nonFractional.date(from: string)
    }

    static func date(fromNumericTimestamp timestamp: Double) -> Date {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000.0 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    static func tokenUsage(from dictionary: JSONDictionary?) -> TokenUsage? {
        guard let dictionary else {
            return nil
        }
        let usage = TokenUsage(
            inputTokens: int(dictionary, keys: ["input_tokens", "inputTokens", "input"]),
            cachedInputTokens: int(dictionary, keys: ["cached_input_tokens", "cachedInputTokens", "cached_input"]),
            outputTokens: int(dictionary, keys: ["output_tokens", "outputTokens", "output"]),
            reasoningOutputTokens: int(dictionary, keys: ["reasoning_output_tokens", "reasoningOutputTokens", "reasoning"]),
            totalTokens: int(dictionary, keys: ["total_tokens", "totalTokens", "total"])
        )
        if usage.inputTokens == nil,
           usage.cachedInputTokens == nil,
           usage.outputTokens == nil,
           usage.reasoningOutputTokens == nil,
           usage.totalTokens == nil {
            return nil
        }
        return usage
    }

    static func truncatedTitle(_ raw: String, maxLength: Int = 80) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else {
            return normalized
        }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
