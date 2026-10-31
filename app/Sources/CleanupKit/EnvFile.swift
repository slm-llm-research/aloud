import Foundation

/// Minimal `.env` reader for importing API keys (KEY=value, optional quotes, `#` comments).
public enum EnvFile {
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line.removeFirst("export ".count) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let q = value.first, q == "\"" || q == "'",
               let close = value.dropFirst().firstIndex(of: q) {
                // Quoted: take up to the matching quote; anything after (e.g. a comment) is ignored.
                value = String(value[value.index(after: value.startIndex)..<close])
            } else if let hash = value.range(of: " #") {
                value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            if !key.isEmpty, !value.isEmpty { out[key] = value }
        }
        return out
    }
}
