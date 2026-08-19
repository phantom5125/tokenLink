import Foundation

public enum DiagnosticExporter {
    public static func sanitize(
        _ value: Any,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        accountLabels: Set<String> = []
    ) -> Any {
        let context = RedactionContext(
            homePath: homeURL.standardizedFileURL.path,
            username: homeURL.lastPathComponent,
            accountLabels: accountLabels)
        return sanitize(value, context: context)
    }

    public static func write(
        _ value: Any,
        to url: URL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        accountLabels: Set<String> = []
    ) throws {
        let safe = sanitize(value, homeURL: homeURL, accountLabels: accountLabels)
        let data = try JSONSerialization.data(
            withJSONObject: safe,
            options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func sanitize(_ value: Any, context: RedactionContext) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = isSensitiveKey(pair.key)
                    ? "<redacted>"
                    : sanitize(pair.value, context: context)
            }
        }
        if let array = value as? [Any] {
            return array.map { sanitize($0, context: context) }
        }
        if let string = value as? String {
            return redact(string, context: context)
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("authorization")
            || normalized.contains("apikey")
    }

    private static func redact(_ input: String, context: RedactionContext) -> String {
        var output = input
        if !context.homePath.isEmpty {
            output = output.replacingOccurrences(of: context.homePath, with: "<home>")
        }
        if !context.username.isEmpty {
            output = output.replacingOccurrences(of: context.username, with: "<user>")
        }
        for label in context.accountLabels.sorted(by: { $0.count > $1.count }) where !label.isEmpty {
            output = output.replacingOccurrences(of: label, with: "<account>")
        }
        output = replacingMatches(
            in: output,
            pattern: #"/Users/[^/\s]+(?:/[^\s\"']*)?"#,
            template: "<home>")
        output = replacingMatches(
            in: output,
            pattern: #"(?i)Bearer\s+[^\s,\"']+"#,
            template: "Bearer <redacted>")
        output = replacingMatches(
            in: output,
            pattern: #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            template: "<device-id>")
        return output
    }

    private static func replacingMatches(
        in value: String,
        pattern: String,
        template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: template)
    }
}

private struct RedactionContext {
    let homePath: String
    let username: String
    let accountLabels: Set<String>
}
