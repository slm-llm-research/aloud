import Foundation

/// Deterministic passes around the LLM: rules do what they can so the model's job stays small, and
/// they run on every path (LLM, skipped, offline, fallback) so output is clean regardless of model.
public enum OutputHygiene {
    /// Legitimate doubled words that must survive repeat collapsing.
    static let allowedDoubles: Set<String> = ["had", "that", "is", "do", "very", "really", "bye", "no", "ha", "so"]

    /// Before the LLM: removes stutters the recognizer wrote out.
    /// - Cut-off fragments: "sub- sub-agent" -> "sub-agent", "I- I think" -> "I think".
    /// - Immediate repeats: "the the" -> "the" (not "had had", "that that", ...).
    public static func collapseStutters(_ s: String) -> String {
        // A word cut off with a hyphen, then restarted with the same letters.
        var t = s.replacingOccurrences(of: "(?i)\\b([\\p{L}\\p{N}]+)-\\s+(?=\\1)", with: "",
                                       options: .regularExpression)
        // Written without the space: "sub-sub-agent" -> "sub-agent" (three parts only, so "bye-bye" stays).
        t = t.replacingOccurrences(of: "(?i)\\b([\\p{L}]{2,})-\\1-(?=[\\p{L}])", with: "$1-", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: "(?i)\\b([\\p{L}']+)(?:\\s+\\1\\b)+") else { return t }
        let ns = t as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: m.range(at: 1))
            // "dash dash watch" is "--watch", not a stutter.
            guard !allowedDoubles.contains(word.lowercased()), !Fidelity.symbolWords.contains(word.lowercased()) else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + word
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        t = out
        return t
    }

    /// Pulls the text out of `<edited>...</edited>`. Untagged output is taken whole. `outside` is any
    /// text the model wrote around the tags ("Sure, here's ..."), a sign it answered instead of edited.
    public static func extractEdited(_ raw: String) -> (text: String, outside: String) {
        guard let open = raw.range(of: "<edited>") else {
            return (raw.replacingOccurrences(of: "</edited>", with: ""), "")
        }
        let afterOpen = raw[open.upperBound...]
        let close = afterOpen.range(of: "</edited>")
        let body = close.map { String(afterOpen[..<$0.lowerBound]) } ?? String(afterOpen)
        let tail = close.map { String(afterOpen[$0.upperBound...]) } ?? ""
        let outside = (String(raw[..<open.lowerBound]) + tail).trimmingCharacters(in: .whitespacesAndNewlines)
        return (body.trimmingCharacters(in: .whitespacesAndNewlines), outside)
    }

    /// After the LLM: plain punctuation that works everywhere (search, code, shells), plus the
    /// shape rules of the mode.
    public static func finish(_ s: String, mode: DictationMode) -> String {
        var t = s
        // Look-alike hyphens and spaces (gpt-oss writes U+2011 non-breaking hyphens).
        for (from, to) in [("\u{2010}", "-"), ("\u{2011}", "-"), ("\u{2012}", "-"), ("\u{2212}", "-"),
                           ("\u{00A0}", " "), ("\u{202F}", " "), ("\u{200B}", "")] {
            t = t.replacingOccurrences(of: from, with: to)
        }
        if mode.isDeveloper {
            // Smart quotes break shells and code.
            for (from, to) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"), ("\u{2019}", "'"),
                               ("\u{2026}", "...")] {
                t = t.replacingOccurrences(of: from, with: to)
            }
        }
        if mode == .terminal {
            // One line, no sentence period: it's a command.
            t = t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            while t.hasSuffix(".") && !t.hasSuffix("..") { t.removeLast() }
            t = commandCase(t)
        }
        if mode == .list { t = listShape(t) }
        if mode == .email { t = emailShape(t) }
        if mode == .chat {
            // Speech-to-text writes "at 5" as "at 5:00"; a chat message keeps it as said.
            t = t.replacingOccurrences(of: "(?i)\\b(\\d{1,2}):00\\b(?!\\s*[ap]\\.?m)", with: "$1",
                                       options: .regularExpression)
        }
        t = t.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// List mode, when the model wrote one sentence instead of a list: "Eggs, 2 litres of milk and
    /// spinach." becomes one "- " line per item. Only a single comma-separated sentence is reshaped;
    /// anything with bullets or several sentences is left alone.
    static func listShape(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // A spoken list name ends up on the first item ("- Grocery list: eggs"): give it its own line.
        if let m = t.range(of: "^[-*•] ([^:\\n]{1,30}):[ \\t]+(?=\\S)", options: .regularExpression) {
            let title = t[m].dropFirst(2).trimmingCharacters(in: .whitespaces)
            let rest = t[m.upperBound...]
            return title + "\n- " + rest.prefix(1).uppercased() + rest.dropFirst()
        }
        // "- Grocery list\n- Eggs\n- Milk": the spoken list name came back as the first item.
        let leadIns = ModeRouter.listLeadIns.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        if let m = t.range(of: "^[-*•] (?i)(" + leadIns + ")[:.,]?[ \\t]*\n", options: .regularExpression),
           t[m.upperBound...].hasPrefix("- ") || t[m.upperBound...].hasPrefix("* ") || t[m.upperBound...].hasPrefix("• ") {
            let head = t[m].dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: ":., \t\n"))
            return head.prefix(1).uppercased() + head.dropFirst() + ":\n" + listShape(String(t[m.upperBound...]))
        }
        // "- To-do list email the landlord": a lead-in without its colon.
        if let m = t.range(of: "^[-*•] (?i)(" + ModeRouter.listLeadIns.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
                           + ")[:,]?\\s+(?=\\S)", options: .regularExpression) {
            let head = t[m].dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: ":, \t"))
            let rest = t[m.upperBound...]
            return head.prefix(1).uppercased() + head.dropFirst() + ":\n- " + rest.prefix(1).uppercased() + rest.dropFirst()
        }
        // "Grocery list: eggs, milk and bread." -> the title, then one item per line.
        var title = ""
        if let m = t.range(of: "^[^:,.\\n]{1,30}:[ \\t]+(?=\\S)", options: .regularExpression), !t.contains("\n") {
            let items = listShape(String(t[m.upperBound...]))
            if items.hasPrefix("- ") {
                title = t[m].trimmingCharacters(in: .whitespaces)
                t = items
            }
        }
        if !title.isEmpty { return title + "\n" + t }
        let hasBullets = t.components(separatedBy: "\n").contains {
            let l = $0.trimmingCharacters(in: .whitespaces)
            return l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") || l.range(of: "^\\d+[.)] ", options: .regularExpression) != nil
        }
        if hasBullets {
            // "- eggs" -> "- Eggs", like the reshaped items below.
            return t.components(separatedBy: "\n").map { line in
                guard line.hasPrefix("- "), let c = line.dropFirst(2).first, c.isLowercase else { return line }
                return "- " + String(c).uppercased() + line.dropFirst(3)
            }.joined(separator: "\n")
        }
        guard !t.contains("\n") else { return t }
        var body = t
        while let last = body.last, ".!".contains(last) { body.removeLast() }
        guard !body.contains(". "), !body.contains("? ") else { return t }
        let items = body.replacingOccurrences(of: ",? and ", with: ", ", options: .regularExpression)
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard items.count >= 2 else { return t }
        return items.map { "- " + $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "\n")
    }

    /// Common commands speech-to-text writes like words: "CD~/projects" -> "cd ~/projects", "Git status" -> "git status".
    static let commands: Set<String> = ["cd", "ls", "git", "npm", "npx", "pnpm", "yarn", "cat", "mkdir", "rm", "mv", "cp",
                                        "grep", "make", "brew", "pip", "python", "python3", "uv", "swift", "docker",
                                        "kubectl", "ssh", "curl", "open", "code", "claude", "node", "go", "cargo"]
    static func commandCase(_ s: String) -> String {
        guard let m = s.range(of: "^[A-Za-z][A-Za-z0-9]*", options: .regularExpression),
              commands.contains(s[m].lowercased()) else { return s }
        let rest = s[m.upperBound...]
        // "cd~/x": the space speech-to-text dropped after the command.
        let space = rest.first.map { "~/.".contains($0) } == true ? " " : ""
        return s[m].lowercased() + space + rest
    }

    static let greetings = "hi|hello|hey|dear|good morning|good afternoon|good evening"
    static let signOffs = "thanks|thank you|thanks again|many thanks|best|best regards|kind regards|warm regards|regards|cheers|sincerely|talk soon"
    static let nameWord = "[A-Z][\\p{L}'-]+"

    /// Email mode: a spoken greeting and sign-off on their own lines ("Hi Sarah. Just checking ...
    /// Thanks. Shekhar." -> "Hi Sarah,\n\nJust checking ...\n\nThanks,\nShekhar"). Only words the
    /// speaker said are moved; nothing is added.
    static func emailShape(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = "\(nameWord)(?: \(nameWord))?"
        // Greeting with a name (or "there", "all", "team", "everyone") and more text after it.
        if let re = try? NSRegularExpression(
            pattern: "^((?i:\(greetings)))[,.!]?[ \\t]+(\(name)|(?i:there|all|team|everyone))[,.!:]?\\s+(?=\\S)"),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let whole = Range(m.range, in: t), let g = Range(m.range(at: 1), in: t), let n = Range(m.range(at: 2), in: t) {
            let greeting = t[g].prefix(1).uppercased() + t[g].dropFirst() + " " + t[n] + ","
            let body = t[whole.upperBound...]
            t = greeting + "\n\n" + body.prefix(1).uppercased() + body.dropFirst()
        }
        // Sign-off, then the speaker's name, at the very end.
        if let re = try? NSRegularExpression(
            pattern: "(^|[.!?,]\\s+|\\n+)((?i:\(signOffs)))[,.!]?\\s+(\(name))[.!]?$"),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let whole = Range(m.range, in: t), let lead = Range(m.range(at: 1), in: t),
           let so = Range(m.range(at: 2), in: t), let n = Range(m.range(at: 3), in: t) {
            var before = String(t[..<whole.lowerBound]) + t[lead].trimmingCharacters(in: .whitespacesAndNewlines)
            if before.hasSuffix(",") { before = String(before.dropLast()) + "." }
            let signOff = t[so].prefix(1).uppercased() + t[so].dropFirst() + ",\n" + t[n]
            // A one-line "Thanks Sarah." is a reply, not a sign-off.
            if !before.isEmpty { t = before + "\n\n" + signOff }
        }
        return t
    }

    /// Starts a new sentence at each match of `before` (its captured word becomes the sentence start),
    /// but only when the sentence so far has at least `minWords` words, so "check and fix it" stays whole.
    static func splitRunOn(_ s: String, before: String, minWords: Int = 3) -> String {
        guard let re = try? NSRegularExpression(pattern: "\\s+(?:" + before + ")", options: [.caseInsensitive]) else { return s }
        var out = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            let word = (1..<m.numberOfRanges).lazy.compactMap { Range(m.range(at: $0), in: s) }.first
            guard let word else { continue }
            let sinceBoundary = (out + s[last..<whole.lowerBound]).components(separatedBy: CharacterSet(charactersIn: ".!?")).last ?? ""
            guard sinceBoundary.split(separator: " ").count >= minWords else { continue }
            var piece = String(s[last..<whole.lowerBound])
            while piece.hasSuffix(",") || piece.hasSuffix(" ") { piece.removeLast() }
            out += piece + ". "
            out += s[word.lowerBound..<whole.upperBound]
            last = whole.upperBound
        }
        return out + s[last...]
    }

    /// "... as a prompt" when the model didn't lay it out: the speaker's own sentences sorted under
    /// Goal, Tasks (one bullet per separate ask, when there are two or more), Context, Constraints
    /// (don't / never / only / make sure ...) and Done when ("until CI is green"). Only labels and
    /// bullets are added; no sentence is reworded.
    public static func promptShape(_ s: String) -> String {
        var flat = s.replacingOccurrences(of: "^\\s*[-*]\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\n+\\s*(?:[-*]\\s+)?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\b(?:goal|tasks|context|constraints|done when):\\s*", with: "", options: .regularExpression)
        let runOn = flat.trimmingCharacters(in: .whitespaces).dropLast().rangeOfCharacter(from: CharacterSet(charactersIn: ".!?")) == nil
        // "Add dark mode and keep the existing colors" -> the "keep ..." clause is its own constraint.
        flat = flat.replacingOccurrences(
            of: ",?\\s+(?:and|but)\\s+((?i:keep|don't|do not|never|avoid|make sure|only)\\b)", with: ". $1",
            options: .regularExpression)
        let verbs = "make|fix|add|write|create|build|run|check|update|remove|delete|change|refactor|explain|tell|show|give|"
            + "find|help|implement|test|push|open|review|move|rename|scan|lint|clean|set up|deploy|migrate|document"
        // "Scan the code base, add linting, and run the tests" -> one ask per comma-separated clause.
        flat = flat.replacingOccurrences(of: ",\\s+(?:and\\s+)?((?i:\(verbs))\\b)", with: ". $1", options: .regularExpression)
        // Run-on speech (no punctuation when every model failed): "... and run the tests", "... and keep
        // going until", "... don't touch X" start new items once the current one has a few words.
        if runOn {
            flat = splitRunOn(flat, before: "(?:and\\s+)((?:\(verbs)|keep|make sure)\\b)|(?<!\\b(?:i|we|you|it|they|that|this|just)\\s)((?:don't|do not|never)\\b)")
        }
        guard let re = try? NSRegularExpression(pattern: "\\S.*?(?:[.!?]+(?=\\s|$)|$)") else { return s }
        let sentences = re.matches(in: flat, range: NSRange(flat.startIndex..., in: flat))
            .compactMap { Range($0.range, in: flat).map { flat[$0].trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let lead = "^(?i)(?:(?:so|and|also|then|ok|okay|hey)[, ]+)*"
        let requests = lead + "(?:(?:can|could|would|will) you\\b|please\\b|i want\\b|i need\\b|i'd like\\b|we need\\b|let's\\b|(?:\(verbs))\\b)"
        let questions = lead + "(?:how|what|why|where|when|which|who|is|are|do|does)\\b"
        // "I don't know why ..." is context, not a rule.
        let rules = "(?i)(?<!\\b(?:i|we|they|it)\\s)\\b(?:don't|dont|do not|never|without|avoid|only|must|make sure|keep)\\b"
        let ruleStart = lead + "(?:don't|dont|do not|never|avoid|only|make sure|keep|without)\\b"
        let doneWhen = "(?i)(?:^(?:it's |it is )?done when\\b|\\buntil\\b.*\\b(?:green|pass|passes|passing|works|succeeds)\\b)"
        var asks: [String] = [], qs: [String] = [], context: [String] = [], constraints: [String] = [], done: [String] = []
        for x in sentences {
            let matches = { (p: String) in x.range(of: p, options: .regularExpression) != nil }
            if matches(doneWhen) { done.append(x) }
            else if matches(ruleStart) { constraints.append(x) }
            else if matches(requests) { asks.append(x) }
            else if matches(rules) { constraints.append(x) }
            else if matches(questions) || x.hasSuffix("?") { qs.append(x) }
            else { context.append(x) }
        }
        // A question leads ("what's the status ...?") and every request becomes a task; without one,
        // the first request is the goal and any further ones are tasks.
        var goal: [String] = qs
        var tasks: [String] = []
        if !goal.isEmpty { tasks = asks }
        else if !asks.isEmpty { goal.append(asks.removeFirst()); tasks = asks }
        if goal.isEmpty, !context.isEmpty { goal.append(context.removeFirst()) }
        if goal.isEmpty { return s }
        var out = ["Goal: " + goal.joined(separator: " ")]
        if !tasks.isEmpty { out.append("Tasks:\n" + tasks.map { "- " + $0 }.joined(separator: "\n")) }
        for (label, items) in [("Context", context), ("Constraints", constraints), ("Done when", done)] where !items.isEmpty {
            out.append("\(label): " + items.joined(separator: " "))
        }
        return out.joined(separator: "\n")
    }
}
