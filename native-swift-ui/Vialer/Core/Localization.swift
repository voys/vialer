import Foundation

/// Strings that only exist in the native app (`native.*`), kept in the in-project
/// `Native.xcstrings` catalog rather than Phrase.
func N(_ key: String, _ args: [String: Any] = [:]) -> String {
    L10nFormat.resolve("native.\(key)", args, table: "Native")
}

/// Resolves Phrase strings that still carry the Flutter i18n placeholder syntax:
/// `$name`, `${name}`, `${_plural(count, one: 'x', many: 'y')}`, `<b>…</b>` and literal `\n`.
enum L10nFormat {
    private static let pluralPattern = try! NSRegularExpression(
        pattern: #"\$\{_plural\((\w+),\s*one:\s*'([^']*)',\s*many:\s*'([^']*)'\)\}"#
    )
    private static let bracedPattern = try! NSRegularExpression(pattern: #"\$\{(\w+)\}"#)
    private static let barePattern = try! NSRegularExpression(pattern: #"\$(\w+)"#)

    static func resolve(_ key: String, _ args: [String: Any] = [:], table: String? = nil) -> String {
        var value = NSLocalizedString(key, tableName: table, comment: "")
        if value == key { AppLog.warning("Missing string: \(key)") }
        value = substitutePlurals(in: value, args: args)
        value = substitute(bracedPattern, in: value, args: args)
        value = substitute(barePattern, in: value, args: args)
        return value
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
            .replacingOccurrences(of: "\\n", with: "\n")
    }

    private static func substitutePlurals(in value: String, args: [String: Any]) -> String {
        let ns = value as NSString
        var result = value
        for match in pluralPattern.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: match.range(at: 1))
            let one = ns.substring(with: match.range(at: 2))
            let many = ns.substring(with: match.range(at: 3))
            let count = (args[name] as? Int) ?? Int("\(args[name] ?? "")") ?? 0
            result = (result as NSString).replacingCharacters(in: match.range, with: count == 1 ? one : many)
        }
        return result
    }

    private static func substitute(_ pattern: NSRegularExpression, in value: String, args: [String: Any]) -> String {
        let ns = value as NSString
        var result = value
        for match in pattern.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: match.range(at: 1))
            guard let arg = args[name] else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: "\(arg)")
        }
        return result
    }
}
