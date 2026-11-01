import Foundation
import Testing
@testable import CleanupKit

@Suite("App profiles")
struct AppProfileTests {
    @Test(arguments: [
        ("com.todesktop.230313mzl4w4u92", AppProfile.codeEditor),  // Cursor
        ("com.microsoft.VSCode", .codeEditor),
        ("com.jetbrains.pycharm", .codeEditor),
        ("com.apple.Terminal", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("com.anthropic.claudefordesktop", .aiChat),
        ("com.openai.chat", .aiChat),
        ("com.tinyspeck.slackmacgap", .general),
        ("net.whatsapp.WhatsApp", .general),
    ])
    func classifiesByBundleID(_ id: String, _ expected: AppProfile) {
        #expect(AppProfiles.classify(AppContext(bundleID: id)) == expected)
    }

    @Test func browserTabsWithAIChatsAreAIChat() {
        #expect(AppProfiles.classify(AppContext(bundleID: "com.google.Chrome", windowTitle: "Claude - Google Chrome")) == .aiChat)
        #expect(AppProfiles.classify(AppContext(bundleID: "com.apple.Safari", windowTitle: "ChatGPT")) == .aiChat)
        #expect(AppProfiles.classify(AppContext(bundleID: "com.google.Chrome", windowTitle: "Inbox (3) - Gmail")) == .general)
    }

    @Test func onlyMentionedTitleTermsAreKept() {
        let terms = ["auth_middleware.ts", "api-server", "SessionStore.swift"]
        #expect(AppProfiles.mentionedTerms(terms, in: "fix the auth middleware dot ts file") == ["auth_middleware.ts"])
        #expect(AppProfiles.mentionedTerms(terms, in: "the session store swift file is wrong") == ["SessionStore.swift"])
        #expect(AppProfiles.mentionedTerms(terms, in: "refactor the parser").isEmpty)
    }

    @Test func noAppIsGeneral() {
        #expect(AppProfiles.classify(AppContext()) == .general)
    }

    @Test func termsFromEditorAndTerminalTitles() {
        #expect(AppProfiles.terms(fromWindowTitle: "auth_middleware.ts — api-server") == ["auth_middleware.ts", "api-server"])
        #expect(AppProfiles.terms(fromWindowTitle: "● Session.swift — Murmur") == ["Session.swift"])
        #expect(AppProfiles.terms(fromWindowTitle: "✳ Fix flaky test — claude — 120×40") == [])
        #expect(AppProfiles.terms(fromWindowTitle: "aloud-app — -zsh — 80×24") == ["aloud-app", "-zsh"])
        #expect(AppProfiles.terms(fromWindowTitle: nil).isEmpty)
    }
}

@Suite("Coding mode cleanup")
struct CodingCleanupTests {
    static let rambling = "okay so the hotkey thing, when I double tap the function key it should latch the mic open, "
        + "and then a single tap closes it, but if I hold it it's push to talk, and oh also escape should cancel, "
        + "and I want the timing configurable, maybe default three hundred milliseconds for the double tap"

    /// Organized with the speaker's own sentences (what the coding-agent mode asks for).
    static let structured = """
    Goal: The hotkey thing: when I double tap the function key, it should latch the mic open, and then a single tap closes it. If I hold it, it's push to talk.
    Constraints:
    - Escape should cancel.
    - I want the timing configurable, maybe default 300 milliseconds for the double tap.
    """

    /// The old template output: tidy, but no longer the speaker's words.
    static let reworded = """
    Goal: Implement push-to-talk with double-tap latch on the function key.
    Requirements:
    - Double-tap latches the mic open; a single tap closes it.
    - Holding the key is push-to-talk.
    - Escape cancels.
    - Timing is configurable; default double-tap window 300 ms.
    """

    @Test func longRequestInCodingAppIsRestructured() async {
        let llm = FakeLLM(name: "groq", reply: Self.structured)
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean(Self.rambling, context: AppContext(bundleID: "com.apple.Terminal", appName: "Terminal"))
        #expect(r.restructured)
        #expect(r.profile == .terminal)
        #expect(r.mode == .codingAgent)
        #expect(r.text == Self.structured)
    }

    @Test func rewordedRestructureIsRejected() async {
        let llm = FakeLLM(name: "groq", reply: Self.reworded)
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean(Self.rambling, context: AppContext(bundleID: "com.apple.Terminal", appName: "Terminal"))
        #expect(r.via == "fallback")
        #expect(r.notes.contains { $0.contains("rejected") })
    }

    @Test func sameRequestInSlackIsOnlyCleaned() async {
        let llm = FakeLLM(name: "groq", reply: "OK, so the hotkey: double-tap latches.")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean(Self.rambling, context: AppContext(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(!r.restructured)
        #expect(r.profile == .general)
        #expect(r.mode == .chat)
    }

    @Test func shortCodingRequestIsCleanedNotRestructured() async {
        let llm = FakeLLM(name: "groq", reply: "Refactor fetchUser to use async/await.")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("refactor fetch user to use async await", context: AppContext(bundleID: "com.microsoft.VSCode"))
        #expect(!r.restructured)
        #expect(r.text == "Refactor fetchUser to use async/await.")
    }

    @Test func codingPromptCarriesAppAndWindowContext() async {
        let llm = FakeLLM(name: "groq", reply: "Fix the bug in auth.ts.")
        _ = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("fix the bug in auth dot ts", context: AppContext(bundleID: "com.todesktop.230313mzl4w4u92",
                                                                    appName: "Cursor", windowTitle: "auth.ts — api"))
        let sent = llm.calls.users.first ?? ""
        #expect(sent.contains("<context>Target app: Cursor"))
        #expect(!sent.contains("auth.ts — api"))  // raw title is not sent...
        #expect(sent.contains("auth.ts"))        // ...only the names in it, as spelling hints
        #expect(sent.contains("auth.ts"))
    }

    @Test func generalAppsGetNoCodingContext() async {
        let llm = FakeLLM(name: "groq", reply: "See you at three.")
        _ = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("see you at three", context: AppContext(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(!(llm.calls.users.first ?? "").contains("<context>"))
    }

    @Test func restructureThatWritesCodeIsRejected() async {
        let llm = FakeLLM(name: "groq", reply: "Here's the implementation:\n```swift\nfunc latch() {}\n```")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean(Self.rambling, context: AppContext(bundleID: "com.apple.Terminal"))
        #expect(r.via == "fallback")
        #expect(!r.restructured)
    }

    @Test func offlineLongCodingRequestFallsBackToPrepass() async {
        let r = await Cleaner(chain: []).clean(Self.rambling, context: AppContext(bundleID: "com.apple.Terminal"))
        #expect(r.via == "offline")
    }
}

@Suite("App-only context line")
struct AppOnlyContextTests {
    let ctx = AppContext(bundleID: "com.apple.Terminal", appName: "Terminal")
    let text = "Goal: Improve the settings UI.\n\nContext: Terminal app.\n\nRequirements:\n- Add a folder picker."
    /// Faithful structure plus the invented app-only Context line.
    static let leaked = CodingCleanupTests.structured.replacingOccurrences(of: "Constraints:", with: "Context: Terminal app.\nConstraints:")

    @Test func dropsContextThatOnlyNamesTheApp() {
        #expect(Cleaner.dropAppOnlyContext(text, context: ctx, spoken: "improve the settings ui")
                == "Goal: Improve the settings UI.\n\nRequirements:\n- Add a folder picker.")
    }

    @Test func keepsItWhenTheSpeakerMentionedTheApp() {
        #expect(Cleaner.dropAppOnlyContext(text, context: ctx, spoken: "in the terminal app improve the settings")
                == text)
    }

    @Test func keepsRealContext() {
        let t = "Goal: Fix it.\nContext: auth.ts in the Terminal app, token refresh error."
        #expect(Cleaner.dropAppOnlyContext(t, context: ctx, spoken: "fix it") == t)
    }

    @Test func liveCaseFromTheLog() async {
        let llm = FakeLLM(name: "groq", reply: Self.leaked)
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean(CodingCleanupTests.rambling, context: ctx)
        #expect(r.restructured)
        #expect(!r.text.contains("Context: Terminal"))
    }
}

@Suite("Restructure guardrail")
struct RestructureGuardrailTests {
    @Test func templateGrowthIsAllowed() {
        #expect(Guardrail.checkRestructure(input: CodingCleanupTests.rambling, output: CodingCleanupTests.structured) == .accept)
    }

    @Test func codeBlocksAreRejected() {
        #expect(Guardrail.checkRestructure(input: "write a function that adds two numbers please and test it",
                                           output: "```py\ndef add(a, b): return a + b\n```") == .reject("contains code"))
    }

    @Test func contextLeaksAreRejected() {
        #expect(Guardrail.checkRestructure(input: "fix the login bug and add a test for it",
                                           output: "Goal: Fix the login bug.\nContext: Window title: auth.ts — api") == .reject("context leak"))
    }

    @Test func essaysAreRejected() {
        let long = Array(repeating: "word", count: 200).joined(separator: " ")
        #expect(Guardrail.checkRestructure(input: "fix the login bug and add a test for it", output: long) != .accept)
    }
}

/// The four rambling coding requests from the M0 benchmark, through the real LLMs, in the coding-agent mode.
/// ALOUD_INTEGRATION=1 GROQ_API_KEY=... ANTHROPIC_API_KEY=... swift test --filter CodingLive
@Suite("CodingLive", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ALOUD_INTEGRATION"] == "1"))
struct CodingLiveTests {
    static let env = ProcessInfo.processInfo.environment
    static let terminal = AppContext(bundleID: "com.apple.Terminal", appName: "Terminal", windowTitle: "api-server — claude")

    /// (transcript, words that must survive, must be organized). Requests that ask for several things must
    /// be organized; a single ask with details may stay as faithful paragraphs.
    static let cases: [(String, [String], Bool)] = [
        ("I want you to, um, look at the auth middleware, and uh, figure out why the token refresh is failing, and then, "
         + "like, write a fix with tests, but don't touch the database layer. Also make sure the existing error logging "
         + "still works and keep the public interface the same.",
         ["auth middleware", "token refresh", "test", "don't touch the database"], true),
        ("So basically what I need is, um, a script that reads all the CSV files in the downloads folder, merges them, "
         + "and, uh, writes one parquet file, and it should skip files that are empty, and print how many rows it wrote "
         + "at the end so I can sanity check it.",
         ["CSV", "parquet", "empty", "sanity check"], false),
        (CodingCleanupTests.rambling, ["double", "latch", "escape", "300"], false),
        ("can you refactor fetch user to use async await, actually also fetch orders, same thing, and make sure the "
         + "error handling still logs to Sentry, don't change the public API, and update the unit tests so they still "
         + "pass afterwards, thanks",
         ["fetch", "orders", "async", "Sentry", "public API", "unit tests"], true),
    ]

    static func run(_ chain: [CleanupLLM]) async {
        let c = Cleaner(chain: chain.map { .init($0, timeout: 1.5) })  // the app's timeouts (x2 for restructure)
        let clock = ContinuousClock()
        for (input, must, organized) in cases {
            let t0 = clock.now
            let r = await c.clean(input, context: terminal)
            let elapsed = clock.now - t0
            #expect(r.via != "fallback", "\(r.notes)")
            if organized {
                #expect(r.restructured, "\(r.via) \(r.notes)")
                #expect(r.text.contains("Goal:"), "\(r.text)")
            }
            for m in must {
                #expect(r.text.lowercased().contains(m.lowercased()), "missing \(m): \(r.text)")
            }
            // The window title is context for spelling, not content: it must not be copied in.
            #expect(!r.text.contains("api-server"), "context leaked: \(r.text)")
            print("--- via \(r.via) in \(elapsed) (\(Prepass.wordCount(input)) -> \(Prepass.wordCount(r.text)) words) \(r.notes.filter { $0.contains("rejected") || $0.contains("failed") })\n\(r.text)")
        }
    }

    /// What the app runs: Groq first, Haiku if Groq fails or is rejected.
    @Test(.enabled(if: env["GROQ_API_KEY"] != nil && env["ANTHROPIC_API_KEY"] != nil)) func productionChain() async {
        await Self.run([OpenAICompatibleLLM.groq(apiKey: Self.env["GROQ_API_KEY"]!),
                        AnthropicLLM(apiKey: Self.env["ANTHROPIC_API_KEY"]!)])
    }

    @Test(.enabled(if: env["ANTHROPIC_API_KEY"] != nil)) func haikuAlone() async {
        await Self.run([AnthropicLLM(apiKey: Self.env["ANTHROPIC_API_KEY"]!)])
    }
}
