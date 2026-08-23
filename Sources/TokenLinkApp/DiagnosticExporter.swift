import Foundation

/// 诊断导出前的递归脱敏：用户名、home 路径、蓝牙 UUID、账户标签与敏感键值。
public struct DiagnosticExporter: Sendable {
    // Regex 字面量类型不是 Sendable，保持在实例计算属性里，避开静态共享状态。
    private var sensitiveKeyPattern: Regex<Substring> { /token|secret|authorization|api[_-]?key/.ignoresCase() }
    private var uuidPattern: Regex<Substring> { /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/ }
    private var homePattern: Regex<Substring> { /\/Users\/[^\/"]+/ }

    public init() {}

    public func redact(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.reduce(into: [String: Any]()) { result, pair in
                if pair.key.contains(sensitiveKeyPattern) {
                    result[pair.key] = "<redacted>"
                } else {
                    result[pair.key] = redact(pair.value)
                }
            }
        case let array as [Any]:
            return array.map(redact)
        case let string as String:
            return redact(string: string)
        default:
            return value
        }
    }

    private func redact(string: String) -> String {
        var result = string
        let username = NSUserName()
        if !username.isEmpty { result = result.replacingOccurrences(of: username, with: "<user>") }
        result = result.replacing(homePattern) { _ in "<home>" }
        result = result.replacing(uuidPattern) { _ in "<uuid>" }
        return result
    }

    /// 脱敏后写入用户选择的 JSON 文件。
    public func export(_ payload: [String: Any], to url: URL) throws {
        let redacted = redact(payload)
        let data = try JSONSerialization.data(
            withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
