import Foundation

/// How much the cleanup may change the speaker's text, least to most invasive
/// (research/06 §6.1 and "Context-Aware Post-Processing for Dictation Apps").
public enum EditLevel: Int, Comparable, Sendable {
    /// Speech-to-text output plus symbol/punctuation formatting only (terminal commands).
    case verbatim
    /// Remove fillers, false starts and repeats, apply self-corrections, fix punctuation, casing and
    /// clear grammar slips. The speaker's words, order and phrasing are otherwise kept. The default.
    case light
    /// Light, then arranged into a list or labelled sections using the speaker's own sentences.
    case structure

    public static func < (a: EditLevel, b: EditLevel) -> Bool { a.rawValue < b.rawValue }
}

/// What the text is for, decided per utterance from the app and any spoken cue.
public enum DictationMode: String, Sendable, CaseIterable {
    case prose        // notes, docs, anything unknown
    case email
    case chat         // Slack, Messages, WhatsApp, ...
    case list         // Reminders, or "grocery list ..." / "make this a list"
    case aiChat       // ChatGPT, Claude, Gemini: one cleaned prompt, never answered
    case codingAgent  // Claude Code, Cursor, Codex: identifiers in code form; long requests organized
    case terminal     // bare shell prompt: one line, symbols as symbols

    /// The edit level the mode starts from. Coding-agent requests can go up to `.structure`, decided
    /// by the model from the content (thinking aloud stays light) or forced by a spoken cue.
    public var baseLevel: EditLevel {
        switch self {
        case .terminal: return .verbatim
        case .list: return .structure
        case .prose, .email, .chat, .aiChat, .codingAgent: return .light
        }
    }

    /// Modes whose text goes to a developer tool, so identifiers belong in code form.
    public var isDeveloper: Bool { self == .codingAgent || self == .terminal }
}

/// The routing decision for one dictation. `reason` is logged with every dictation for error analysis.
public struct Route: Equatable, Sendable {
    public var mode: DictationMode
    public var reason: String
    /// The transcript with any spoken routing cue ("... as a prompt") removed.
    public var transcript: String
    /// The speaker asked for structure explicitly ("as a prompt", "make this a list").
    public var forceStructure: Bool = false
}

/// Picks the mode with a fixed precedence and stops at the first match: spoken cue, then app rules,
/// then the default (prose at the light level). Never defaults to a more invasive level.
public enum ModeRouter {
    static let emailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.superhuman.electron", "com.readdle.smartemail-Mac",
        "com.mimestream.Mimestream", "com.google.Gmail", "it.bloop.airmail2", "com.freron.MailMate",
    ]
    static let chatApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "com.hnc.Discord", "ru.keepcoder.Telegram",
        "org.whispersystems.signal-desktop", "com.facebook.archon",
    ]
    static let listApps: Set<String> = ["com.apple.reminders", "com.culturedcode.ThingsMac", "com.todoist.mac.Todoist"]
    static let emailTitleMarkers = ["gmail", "outlook", "inbox", "compose", "superhuman", "proton mail"]
    static let chatTitleMarkers = ["slack", "whatsapp", "discord", "messenger", "teams"]
    /// Terminal window titles that show a CLI coding agent running (Terminal.app shows the process name;
    /// Claude Code sets a "✳ ..." title).
    static let agentTitleMarkers = ["claude", "codex", "aider", "gemini", "cursor-agent", "opencode", "✳"]
    static let shellTitleMarkers = ["zsh", "bash", "fish", "-sh", "nu "]
    /// A bare shell rarely receives long dictation; past this it's almost certainly an agent we didn't spot.
    static let maxShellWords = 25

    static let promptCues = ["as a prompt", "make this a prompt", "make that a prompt", "make it a prompt",
                             "turn this into a prompt", "prompt mode"]
    /// Words just before a trailing cue that mean the speaker is talking about the phrase.
    static let talkingAbout: Set<String> = ["is", "was", "it's", "that's", "this", "that", "like", "phrase", "say", "said",
                                            "saying", "says", "called", "xyz", "something", "word", "words", "mention"]
    static let listCues = ["make this a list", "make that a list", "make it a list", "as a list", "list mode"]
    /// Lead-ins that name a list ("grocery list eggs milk ..."). Kept in the text: the model turns
    /// them into nothing or a short title.
    static let listLeadIns = ["grocery list", "shopping list", "to do list", "to-do list", "todo list",
                              "packing list", "checklist", "check list", "list of things"]

    /// Chat words speech-to-text mishears, worst in noise ("lol" -> "love" / "L-O-L"). Sent as
    /// speech-to-text keyterms only when dictating into a chat app, so they can't leak into prose.
    /// Kept short: in the replay eval, "lmao" as a keyterm turned a noisy "lol" into "Lmao".
    static let chatKeyterms = ["lol", "omg", "btw", "idk", "tbh", "brb"]

    /// Extra speech-to-text keyterms for the app the dictation starts in.
    public static func sttKeyterms(bundleID: String?) -> [String] {
        guard let id = bundleID, chatApps.contains(id) else { return [] }
        return chatKeyterms
    }

    public static func route(_ transcript: String, context: AppContext) -> Route {
        // 1. Spoken cue at the start or end, stripped from the text.
        if let stripped = strip(cues: promptCues, from: transcript) {
            return Route(mode: .codingAgent, reason: "spoken cue: prompt", transcript: stripped, forceStructure: true)
        }
        if let stripped = strip(cues: listCues, from: transcript) {
            return Route(mode: .list, reason: "spoken cue: list", transcript: stripped, forceStructure: true)
        }
        let opening = transcript.lowercased().split(separator: " ").prefix(8).joined(separator: " ")
        if let cue = listLeadIns.first(where: { opening.contains($0) }) {
            return Route(mode: .list, reason: "spoken cue: \(cue)", transcript: transcript)
        }

        // 2. App rules.
        let title = context.windowTitle?.lowercased() ?? ""
        let words = Prepass.wordCount(transcript)
        switch AppProfiles.classify(context) {
        case .codeEditor:
            return Route(mode: .codingAgent, reason: "app: code editor", transcript: transcript)
        case .terminal:
            if agentTitleMarkers.contains(where: title.contains) {
                return Route(mode: .codingAgent, reason: "app: terminal running an agent", transcript: transcript)
            }
            if shellTitleMarkers.contains(where: title.contains), words <= maxShellWords {
                return Route(mode: .terminal, reason: "app: terminal at a shell prompt", transcript: transcript)
            }
            return Route(mode: .codingAgent, reason: "app: terminal", transcript: transcript)
        case .aiChat:
            return Route(mode: .aiChat, reason: "app: AI chat", transcript: transcript)
        case .general:
            break
        }
        if let id = context.bundleID {
            if emailApps.contains(id) { return Route(mode: .email, reason: "app: email", transcript: transcript) }
            if chatApps.contains(id) { return Route(mode: .chat, reason: "app: chat", transcript: transcript) }
            if listApps.contains(id) { return Route(mode: .list, reason: "app: lists", transcript: transcript) }
            if AppProfiles.browsers.contains(id) {
                if emailTitleMarkers.contains(where: title.contains) {
                    return Route(mode: .email, reason: "web: email", transcript: transcript)
                }
                if chatTitleMarkers.contains(where: title.contains) {
                    return Route(mode: .chat, reason: "web: chat", transcript: transcript)
                }
            }
        }

        // 3. Default: keep the speaker's words.
        return Route(mode: .prose, reason: "default", transcript: transcript)
    }

    /// Removes a cue phrase spoken at the very start or end ("as a prompt, fix the login bug" /
    /// "... fix the login bug as a prompt"). Nil if none was spoken there.
    static func strip(cues: [String], from transcript: String) -> String? {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let t = transcript.trimmingCharacters(in: trimSet)
        let lower = t.lowercased()
        for cue in cues {
            if lower.hasPrefix(cue) {
                let rest = String(t.dropFirst(cue.count)).trimmingCharacters(in: trimSet)
                if !rest.isEmpty { return rest }
            }
            if lower.hasSuffix(cue) {
                let rest = String(t.dropLast(cue.count)).trimmingCharacters(in: trimSet)
                // "... that this is XYZ as a prompt": talking about the phrase, not asking for it.
                let before = rest.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).suffix(2).map(String.init)
                if before.contains(where: talkingAbout.contains) { continue }
                if !rest.isEmpty { return rest }
            }
        }
        return nil
    }
}
