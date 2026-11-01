import Foundation

/// Deterministic, instant cleanup that runs before (or instead of) the LLM (PLAN.md §4).
///
/// It only does what is safe without understanding: removing pure hesitation sounds. It never tries
/// to resolve self-corrections itself (M0 showed even small LLMs get those wrong); it just detects
/// them so the LLM is called when needed.
public enum Prepass {
    public struct Result: Equatable, Sendable {
        public var text: String
        /// True when the text has things only the LLM can fix well.
        public var needsLLM: Bool
        public var reasons: [String]
    }

    /// Hesitation sounds that never carry meaning. ("like", "you know", "I mean" can be meaningful,
    /// so those are left to the LLM.)
    static let hesitations = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "ah", "hmm", "mm"]

    /// Phrases that usually signal a self-correction or verbal filler worth an LLM pass.
    static let markers = [
        "actually", "no wait", "wait no", "scratch that", "i mean", "sorry", "make that", "rather",
        "let me rephrase", "correction", "you know", "like,", "kind of like", "sort of",
    ]

    public static let maxWordsWithoutLLM = 12

    static func removeBetweenCommas(_ text: String, sounds: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(?i),\\s*\\b(?:" + sounds + ")\\b,\\s*") else { return text }
        var out = ""
        var last = text.startIndex
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            // The sentence around the match: another comma in it means a comma-separated list.
            let start = text[..<r.lowerBound].lastIndex(where: { ".!?".contains($0) }).map { text.index(after: $0) } ?? text.startIndex
            let end = text[r.upperBound...].firstIndex(where: { ".!?".contains($0) }) ?? text.endIndex
            // Count the commas left once hesitations are gone: "Um, so we should, uh, move" has none,
            // "I need eggs, uh, meatloaf, bread loaf, and pasta" has two.
            let sentence = String(text[start..<end]).replacingOccurrences(
                of: "(?i),?\\s*\\b(?:" + sounds + ")\\b,?", with: "", options: .regularExpression)
            let isList = sentence.filter { $0 == "," }.count >= 2
            out += text[last..<r.lowerBound] + (isList ? ", " : " ")
            last = r.upperBound
        }
        return out + text[last...]
    }

    public static func run(_ input: String) -> Result {
        var reasons: [String] = []
        var text = input

        let sounds = hesitations.joined(separator: "|")
        // ", uh," between two words goes with both commas ("should, uh, move" -> "should move"), except
        // between list items, where one comma is the separator ("eggs, uh, meatloaf, bread").
        let withoutHesitations = removeBetweenCommas(text, sounds: sounds)
            .replacingOccurrences(of: "(?i)\\b(" + sounds + ")\\b[,.]?\\s*", with: "", options: .regularExpression)
        if withoutHesitations != text { reasons.append("hesitations") }
        text = tidy(withoutHesitations)

        if hasCorrectionMarker(text) { reasons.append("correction/filler phrase") }
        if hasRepeatedWord(text) { reasons.append("repeated word") }
        if wordCount(text) > maxWordsWithoutLLM { reasons.append("long") }
        if let last = text.last, !".?!:;\"')".contains(last) { reasons.append("no final punctuation") }

        // Hesitations alone are fully handled here; everything else benefits from the LLM.
        let needsLLM = reasons.contains { $0 != "hesitations" }
        return Result(text: text, needsLLM: needsLLM, reasons: reasons)
    }

    /// A self-correction or filler phrase, ignoring the punctuation speech-to-text puts inside it
    /// ("No, wait, Friday" contains "no wait").
    public static func hasCorrectionMarker(_ s: String) -> Bool {
        let lower = " " + s.lowercased() + " "
        let bare = " " + lower.replacingOccurrences(of: "[^a-z0-9' ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression) + " "
        return markers.contains { lower.contains(" " + $0) || bare.contains(" " + $0 + " ") }
    }

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func hasRepeatedWord(_ s: String) -> Bool {
        let words = s.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" })
        return zip(words, words.dropFirst()).contains { $0 == $1 && $0.count > 1 }
    }

    /// Fixes spacing and capitalization left behind after removing words.
    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: ",{2,}", with: ",", options: .regularExpression)
        t = t.replacingOccurrences(of: "^[,.;:\\s]+", with: "", options: .regularExpression)
        // "Um, so we..." -> "So we...": removing a leading hesitation leaves a lowercase start.
        t = capitalizeSentenceStarts(t)
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func capitalizeSentenceStarts(_ s: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in s {
            if capitalizeNext, ch.isLetter {
                out.append(contentsOf: ch.uppercased())
                capitalizeNext = false
            } else {
                out.append(ch)
                if ".!?".contains(ch) { capitalizeNext = true } else if !ch.isWhitespace { capitalizeNext = false }
            }
        }
        return out
    }
}
