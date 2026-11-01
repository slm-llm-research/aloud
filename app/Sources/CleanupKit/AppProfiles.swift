import Foundation

/// Where the text is going, as far as cleanup is concerned (PLAN.md §5).
public enum AppProfile: String, Equatable, Sendable {
    /// Everything else: normal dictation cleanup.
    case general
    /// Code editors (the editor itself or its agent panel): identifiers matter.
    case codeEditor
    /// Terminals, where CLI agents (Claude Code, Codex, aider) and shells live.
    case terminal
    /// Chat with an AI (Claude / ChatGPT / Gemini apps or sites).
    case aiChat

    /// Profiles where long requests are restructured into an agent instruction.
    public var isCoding: Bool { self != .general }
}

/// What we know about the focused app when the key is released.
public struct AppContext: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var windowTitle: String?
    /// The transcript came from a recognizer that mishears more (the on-device fallback): always run
    /// the model so it can repair misheard words, even when the text otherwise looks clean.
    public var repairRecognition: Bool

    public init(bundleID: String? = nil, appName: String? = nil, windowTitle: String? = nil,
                repairRecognition: Bool = false) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.repairRecognition = repairRecognition
    }
}

public enum AppProfiles {
    static let editors: Set<String> = [
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.apple.dt.Xcode",
        "com.google.antigravity",
        "com.openai.codex",  // Codex app: a coding agent's prompt box
    ]
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
    ]
    static let aiChatApps: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.chat", "com.google.GeminiMacOS", "com.google.Gemini",
    ]
    static let browsers: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.brave.Browser", "org.mozilla.firefox", "com.microsoft.edgemac",
    ]
    /// Browser tab titles of AI chat sites.
    static let aiChatTitleMarkers = ["claude", "chatgpt", "gemini", "perplexity"]

    public static func classify(_ ctx: AppContext) -> AppProfile {
        guard let id = ctx.bundleID else { return .general }
        if editors.contains(id) || id.hasPrefix("com.jetbrains.") { return .codeEditor }
        if terminals.contains(id) { return .terminal }
        if aiChatApps.contains(id) { return .aiChat }
        if browsers.contains(id), let title = ctx.windowTitle?.lowercased(),
           aiChatTitleMarkers.contains(where: { title.contains($0) }) {
            return .aiChat
        }
        return .general
    }

    /// File and project names from an editor/terminal window title, e.g.
    /// "auth_middleware.ts — api-server" -> ["auth_middleware.ts", "api-server"]. They become
    /// spelling hints, so "auth middleware dot ts" can come out as `auth_middleware.ts`.
    public static func terms(fromWindowTitle title: String?) -> [String] {
        guard let title, !title.isEmpty else { return [] }
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "—–|·•"))
            .flatMap { $0.components(separatedBy: " - ") }
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "●✳*"))) }
        var out: [String] = []
        for p in parts where !p.isEmpty && !p.contains(" ") && p.count <= 60 {
            // Keep things that look like files, paths or identifiers, not plain words like "Terminal".
            let looksCodey = p.contains(".") || p.contains("_") || p.contains("-") || p.contains("/")
                || p.dropFirst().contains(where: \.isUppercase)
            if looksCodey, !out.contains(p) { out.append(p) }
        }
        return out
    }

    /// Keeps only the title terms the speaker seems to have said: every word of the term (split on
    /// . _ - / and camelCase, ignoring 1-2 letter parts like "ts") must appear in the transcript.
    /// "auth dot ts" keeps `auth.ts`; a project name nobody mentioned is dropped, so the LLM can't
    /// add it to the text.
    public static func mentionedTerms(_ terms: [String], in transcript: String) -> [String] {
        let spoken = Set(transcript.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return terms.filter { term in
            let parts = spokenParts(of: term).filter { $0.count >= 3 }
            return !parts.isEmpty && parts.allSatisfy { spoken.contains($0) }
        }
    }

    static func spokenParts(of term: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for ch in term {
            if !ch.isLetter && !ch.isNumber {
                if !current.isEmpty { parts.append(current) }
                current = ""
            } else if ch.isUppercase, let last = current.last, last.isLowercase {
                parts.append(current)
                current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.map { $0.lowercased() }
    }
}
