import Foundation

/// Measures whether cleaned text still uses the speaker's words: content-word recall (input words kept)
/// and precision (output words the speaker actually said). Grammar words, fillers and spoken symbol
/// words ("dash", "comma") don't count, so ordinary cleanup and formatting pass.
public enum Fidelity {
    public struct Report: Equatable, Sendable {
        /// Input content words missing from the output.
        public var missing: [String]
        /// Output content words the speaker never said.
        public var novel: [String]
        public var inputCount: Int
        public var outputCount: Int
    }

    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "so", "to", "of", "in", "on", "at", "for", "by",
        "with", "from", "as", "into", "about", "up", "out", "is", "are", "was", "were", "be", "been", "being",
        "am", "do", "does", "did", "have", "has", "had", "will", "would", "can", "could", "should", "shall",
        "may", "might", "must", "it", "its", "this", "that", "these", "those", "there", "here", "i", "me", "my",
        "we", "us", "our", "you", "your", "he", "she", "him", "her", "they", "them", "their", "what", "which",
        "who", "whom", "also", "too", "just", "not", "s", "t", "ll", "re", "ve", "d", "m", "let", "lets",
        "all", "any", "some", "one", "please",
    ]
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "erm", "er", "ah", "hmm", "mm", "like", "know", "mean", "okay", "ok",
        "basically", "actually", "well", "yeah", "kind", "sort", "wait", "scratch", "sorry", "rather",
        "literally", "right", "alright",
    ]
    /// Spoken punctuation and symbols that become characters in the output.
    static let symbolWords: Set<String> = [
        "dash", "hyphen", "slash", "backslash", "dot", "period", "comma", "colon", "semicolon", "underscore",
        "tilde", "pipe", "star", "asterisk", "equals", "plus", "minus", "quote", "quotes", "apostrophe",
        "hash", "pound", "dollar", "percent", "ampersand", "bracket", "brackets", "paren", "parens",
        "parenthesis", "open", "close", "new", "line", "paragraph", "bullet", "point", "question", "mark",
        "exclamation", "caret", "backtick", "greater", "less", "than", "space", "tab", "enter",
    ]
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
        "first", "second", "third", "half", "point",
    ]
    /// Labels the structure levels add ("Goal:", "Done when:").
    static let labelWords: Set<String> = ["goal", "context", "constraints", "constraint", "requirements", "done",
                                         "when", "steps", "notes"]

    /// Words, split on anything that isn't a letter or digit and on camelCase boundaries, lowercased:
    /// "fetchUser" -> fetch, user; "auth.ts" -> auth, ts; "don't" -> don, t.
    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var prev: Character?
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if let p = prev, ch.isUppercase, p.isLowercase, !cur.isEmpty {
                    out.append(cur.lowercased())
                    cur = ""
                }
                cur.append(ch)
            } else if !cur.isEmpty {
                out.append(cur.lowercased())
                cur = ""
            }
            prev = ch
        }
        if !cur.isEmpty { out.append(cur.lowercased()) }
        return out
    }

    static func isContent(_ w: String) -> Bool {
        !stopwords.contains(w) && !fillers.contains(w) && !symbolWords.contains(w) && !labelWords.contains(w)
            && (w.count >= 2 || w.first?.isNumber == true)
    }

    public static func compare(input: String, output: String, allowed: [String] = []) -> Report {
        let inAll = tokens(input)
        let outAll = tokens(output)
        let inSet = Set(inAll)
        let outSet = Set(outAll)
        let allowedSet = Set(allowed.flatMap(tokens))
        let inContent = Set(inAll.filter(isContent))
        let outContent = Set(outAll.filter(isContent))
        let inHasNumber = inAll.contains { numberWords.contains($0) || $0.first?.isNumber == true }
        let outHasNumber = outAll.contains { $0.first?.isNumber == true || numberWords.contains($0) }
        // Two or three adjacent input words written as one ("fast api" -> FastAPI, "to do" -> todo).
        var joined = Set<String>()
        for n in 2...3 where inAll.count >= n {
            for i in 0...(inAll.count - n) { joined.insert(inAll[i..<(i + n)].joined()) }
        }

        let missing = inContent.filter { w in
            if outSet.contains(w) { return false }
            if numberWords.contains(w) && outHasNumber { return false }
            // Merged into a longer output word ("fast" in "fastapi").
            if w.count >= 3, outSet.contains(where: { $0.count > w.count && $0.contains(w) }) { return false }
            return true
        }.sorted()
        let novel = outContent.filter { w in
            if inSet.contains(w) || allowedSet.contains(w) || joined.contains(w) { return false }
            if w.first?.isNumber == true && inHasNumber { return false }
            return true
        }.sorted()
        return Report(missing: missing, novel: novel, inputCount: inContent.count, outputCount: outContent.count)
    }

    /// not / never / no / nothing / don't-style words (with or without the apostrophe, since speech-to-text
    /// writes "dont"): a dropped or added one flips the meaning.
    public static func negations(_ s: String) -> Int {
        let t = s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        guard let re = try? NSRegularExpression(
            pattern: "\\b(not|never|no|none|nothing|nobody|nowhere|cannot|neither|nor|[a-z]+n't|dont|doesnt|didnt|cant|wont|isnt|arent|wasnt|werent|shouldnt|wouldnt|couldnt|havent|hasnt|hadnt|aint|mustnt)\\b") else { return 0 }
        return re.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t))
    }

    /// Digit sequences ("3", "300", "2026").
    public static func numbers(_ s: String) -> Set<String> {
        // "6:00" and "6" are the same time: the ":00" is formatting, not a number that can be dropped.
        let s = s.replacingOccurrences(of: "(\\d):00\\b", with: "$1", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: "\\d+") else { return [] }
        let ns = s as NSString
        return Set(re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
    }
}
