import Foundation

/// Your own words: terms to always spell right, and fixes for things the recognizer keeps mishearing.
///
/// File format (one entry per line, `#` comments):
///
///     Postgres                 # a term: sent to the recognizer as a keyterm and to the LLM
///     post gress -> Postgres   # a fix: "post gress" in the transcript becomes "Postgres"
///     cload code -> Claude Code
public struct PersonalDictionary: Equatable, Sendable {
    public struct Replacement: Equatable, Sendable {
        public var spoken: String
        public var written: String
    }

    public var terms: [String]
    public var replacements: [Replacement]

    public init(terms: [String] = [], replacements: [Replacement] = []) {
        self.terms = terms
        self.replacements = replacements
    }

    public static func parse(_ text: String) -> PersonalDictionary {
        var d = PersonalDictionary()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let arrow = line.range(of: "->") {
                let spoken = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let written = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !spoken.isEmpty, !written.isEmpty else { continue }
                d.replacements.append(Replacement(spoken: spoken, written: written))
                if !d.terms.contains(written) { d.terms.append(written) }
            } else if !d.terms.contains(line) {
                d.terms.append(line)
            }
        }
        return d
    }

    /// Keyterms for streaming STT. ElevenLabs realtime takes at most 50, each ≤ 20 characters.
    public func keyterms(limit: Int = 50, maxLength: Int = 20) -> [String] {
        Array(terms.filter { $0.count <= maxLength }.prefix(limit))
    }

    /// Applies the fixes, case-insensitively and on whole words only.
    public func apply(_ text: String) -> String {
        var out = text
        for r in replacements {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: r.spoken)
                + "(?![\\p{L}\\p{N}])"
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: r.written),
                                           options: .regularExpression)
        }
        return out
    }
}
