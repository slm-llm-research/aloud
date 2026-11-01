import Foundation
import Testing
@testable import CleanupKit

@Suite("Mode routing")
struct ModeRoutingTests {
    func mode(_ t: String, _ id: String? = nil, title: String? = nil) -> DictationMode {
        ModeRouter.route(t, context: AppContext(bundleID: id, windowTitle: title)).mode
    }

    @Test(arguments: [
        ("com.apple.mail", DictationMode.email),
        ("com.microsoft.Outlook", .email),
        ("com.tinyspeck.slackmacgap", .chat),
        ("com.apple.MobileSMS", .chat),
        ("com.apple.reminders", .list),
        ("com.todesktop.230313mzl4w4u92", .codingAgent),
        ("com.microsoft.VSCode", .codingAgent),
        ("com.openai.chat", .aiChat),
        ("com.google.GeminiMacOS", .aiChat),
        ("com.apple.Notes", .prose),
        ("com.apple.iWork.Pages", .prose),
    ])
    func appRules(id: String, expected: DictationMode) {
        #expect(mode("see you at three tomorrow then", id) == expected)
    }

    @Test func unknownAppIsProse() {
        #expect(mode("hello there") == .prose)
    }

    @Test func browserTabsPickEmailChatAndAIChat() {
        #expect(mode("thanks for the deck", "com.google.Chrome", title: "Inbox (3) - me@gmail.com - Gmail") == .email)
        #expect(mode("lol yeah", "com.google.Chrome", title: "general - Acme - Slack") == .chat)
        #expect(mode("what is a monad", "com.apple.Safari", title: "ChatGPT") == .aiChat)
        #expect(mode("best ramen near capitol hill", "com.google.Chrome", title: "Google") == .prose)
    }

    @Test func terminalAgentVersusShell() {
        let t = "com.apple.Terminal"
        #expect(mode("run the tests", t, title: "aloud — claude — 120×40") == .codingAgent)
        #expect(mode("run the tests", t, title: "✳ Fix login bug") == .codingAgent)
        #expect(mode("git checkout dash b fix slash auth", t, title: "aloud — -zsh — 80×24") == .terminal)
        // Long dictation at what looks like a shell is almost certainly an agent we couldn't see.
        let long = Array(repeating: "word", count: 30).joined(separator: " ")
        #expect(mode(long, t, title: "-zsh") == .codingAgent)
        // Unknown title: coding agent (light edits for short text, so a wrong guess costs little).
        #expect(mode("run the tests", t) == .codingAgent)
    }

    @Test func spokenCuesWinOverTheAppAndAreStripped() {
        let r = ModeRouter.route("fix the login bug and add a test, as a prompt",
                                 context: AppContext(bundleID: "com.apple.Notes"))
        #expect(r.mode == .codingAgent)
        #expect(r.forceStructure)
        #expect(r.transcript == "fix the login bug and add a test")

        let l = ModeRouter.route("Make this a list. eggs, milk and spinach", context: AppContext(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(l.mode == .list)
        #expect(l.transcript == "eggs, milk and spinach")
    }

    @Test func groceryListLeadInIsAListButKeepsItsWords() {
        let r = ModeRouter.route("grocery list eggs two litres of milk and some spinach", context: AppContext())
        #expect(r.mode == .list)
        #expect(r.transcript.hasPrefix("grocery list"))
        #expect(!r.forceStructure)
    }

    @Test func cueInTheMiddleIsJustWords() {
        let r = ModeRouter.route("I wrote it as a prompt for the agent yesterday", context: AppContext())
        #expect(r.mode == .prose)
        #expect(r.transcript == "I wrote it as a prompt for the agent yesterday")
    }

    @Test func levels() {
        #expect(DictationMode.prose.baseLevel == .light)
        #expect(DictationMode.terminal.baseLevel == .verbatim)
        #expect(DictationMode.list.baseLevel == .structure)
        #expect(EditLevel.light < .structure)
    }
}

@Suite("Output hygiene")
struct OutputHygieneTests {
    /// The real case from the log: "sub- sub-agent" was typed as "sub‑sub-agent".
    @Test func collapsesCutOffFragments() {
        #expect(OutputHygiene.collapseStutters("the research done by the sub- sub-agent?") == "the research done by the sub-agent?")
        #expect(OutputHygiene.collapseStutters("I- I think so") == "I think so")
        #expect(OutputHygiene.collapseStutters("pre- and post-processing") == "pre- and post-processing")
    }

    @Test func collapsesRepeatsButKeepsRealDoubles() {
        #expect(OutputHygiene.collapseStutters("we we should move the the launch") == "we should move the launch")
        #expect(OutputHygiene.collapseStutters("I had had enough, and that that was it") == "I had had enough, and that that was it")
    }

    @Test func plainHyphensAndSpacesEverywhere() {
        #expect(OutputHygiene.finish("post\u{2011}processing\u{00A0}works", mode: .prose) == "post-processing works")
    }

    @Test func straightQuotesOnlyForDeveloperModes() {
        #expect(OutputHygiene.finish("run \u{201C}npm test\u{201D}", mode: .codingAgent) == "run \"npm test\"")
        #expect(OutputHygiene.finish("She said \u{201C}hi\u{201D}", mode: .prose) == "She said \u{201C}hi\u{201D}")
    }

    @Test func terminalIsOneLineWithoutAPeriod() {
        #expect(OutputHygiene.finish("git checkout -b fix/auth.\n", mode: .terminal) == "git checkout -b fix/auth")
        #expect(OutputHygiene.finish("ls\n-la", mode: .terminal) == "ls -la")
    }

    @Test func listModeReshapesASentenceIntoItems() {
        #expect(OutputHygiene.finish("Eggs, two litres of milk, some spinach, and a loaf of sourdough.", mode: .list)
                == "- Eggs\n- Two litres of milk\n- Some spinach\n- A loaf of sourdough")
        #expect(OutputHygiene.finish("- Eggs\n- Milk", mode: .list) == "- Eggs\n- Milk")
        #expect(OutputHygiene.finish("Buy milk. Then call mom, dad and Sam.", mode: .list) == "Buy milk. Then call mom, dad and Sam.")
        #expect(OutputHygiene.finish("Eggs, milk", mode: .prose) == "Eggs, milk")
    }

    @Test func extractsEditedTags() {
        #expect(OutputHygiene.extractEdited("<edited>Hi there.</edited>") == ("Hi there.", ""))
        #expect(OutputHygiene.extractEdited("Hi there.") == ("Hi there.", ""))
        let answered = OutputHygiene.extractEdited("Sure! <edited>Paris.</edited>")
        #expect(answered.text == "Paris.")
        #expect(answered.outside == "Sure!")
    }
}

@Suite("Fidelity guardrail")
struct FidelityTests {
    func check(_ input: String, _ output: String, _ level: EditLevel = .light, terms: [String] = []) -> Guardrail.Verdict {
        Guardrail.check(input: input, output: output, level: level, terms: terms)
    }

    @Test func faithfulCleanupPasses() {
        #expect(check("so um I was thinking that maybe we we should move the launch I don't think the docs are ready",
                      "So I was thinking that maybe we should move the launch. I don't think the docs are ready.") == .accept)
    }

    @Test func paraphraseIsRejected() {
        let v = check("so um I was thinking that maybe we we should move the launch I don't think the docs are ready",
                      "We should postpone the release because documentation is incomplete.")
        #expect(v != .accept)
    }

    @Test func identifiersAndNumbersInCodeFormPass() {
        #expect(check("refactor fetch user to use async await in auth dot ts", "Refactor `fetchUser` to use async/await in `auth.ts`.") == .accept)
        #expect(check("ask claude code to add a fast api route", "Ask Claude Code to add a FastAPI route.") == .accept)
        #expect(check("git checkout dash b fix slash auth", "git checkout -b fix/auth", .verbatim) == .accept)
        #expect(check("default three hundred milliseconds", "Default 300 milliseconds.") == .accept)
    }

    @Test func droppedOrAddedNegationIsRejected() {
        #expect(check("don't touch the UI layer and fix the handler", "Touch the UI layer and fix the handler.") == .reject("negation changed 1->0"))
        #expect(check("touch the UI layer", "Don't touch the UI layer.") == .reject("negation changed 0->1"))
    }

    @Test func selfCorrectionMayDropWordsAndNumbers() {
        #expect(check("move it to thursday actually friday at 3 no wait 4", "Move it to Friday at 4.") == .accept)
    }

    @Test func droppedNumberIsRejected() {
        #expect(check("set the timeout to 30 seconds and retries to 5", "Set the timeout to 30 seconds and retries.") == .reject("dropped a number"))
    }

    @Test func answeringIsRejected() {
        #expect(Guardrail.check(input: "what is the capital of france", output: "Paris.", level: .light, outside: "Sure!")
                == .reject("answered, not edited"))
        #expect(check("write a function that adds two numbers", "```py\ndef add(a, b): return a + b\n```") == .reject("contains code"))
    }

    @Test func fusedStutterIsRejected() {
        #expect(check("what did the sub sub agent find", "What did the sub-sub-agent find?") == .reject("fused stutter: sub-sub"))
    }

    @Test func structureMayAddLabelsButNotWords() {
        #expect(check(CodingCleanupTests.rambling, CodingCleanupTests.structured, .structure) == .accept)
        #expect(check(CodingCleanupTests.rambling, CodingCleanupTests.reworded, .structure) != .accept)
    }

    @Test func dictionaryTermsCountAsTheSpeakersWords() {
        #expect(check("open cload code and fix it", "Open Claude Code and fix it.", terms: ["Claude Code"]) == .accept)
    }
}

@Suite("Cleaner modes end to end (fake LLM)")
struct CleanerModeTests {
    @Test func stutterNeverReachesTheModelOrTheScreen() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>What is the update on the research done by the sub-agent?</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("so what is the update on the research done for, by the sub- sub-agent")
        #expect(llm.calls.users.first?.contains("sub- sub") == false)
        #expect(r.text == "What is the update on the research done by the sub-agent?")
    }

    @Test func unicodeHyphensFromTheModelArePlain() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>Add backend post\u{2011}processing to clean the output.</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean("add backend post processing to clean the output")
        #expect(r.text == "Add backend post-processing to clean the output.")
    }

    @Test func modeBlockFollowsTheRoute() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>- Eggs\n- 2 litres of milk\n- Spinach</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean("grocery list eggs two litres of milk and some spinach")
        #expect(r.mode == .list)
        #expect(r.restructured)
        #expect(r.text == "Grocery list:\n- Eggs\n- 2 litres of milk\n- Spinach")
    }

    @Test func emailKeepsTheSpeakersWords() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>Dear Priya,\n\nI am writing to express my gratitude for the deck.</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("hi priya thanks for the deck it looks great", context: AppContext(bundleID: "com.apple.mail"))
        #expect(r.via == "fallback")  // reworded greeting and body: rejected
        #expect(r.mode == .email)
    }

    @Test func shortShellCommandSkipsTheModelWhenNothingIsSpoken() async {
        let llm = FakeLLM(name: "groq", reply: "SHOULD NOT BE USED")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("npm test", context: AppContext(bundleID: "com.apple.Terminal", windowTitle: "-zsh"))
        #expect(r.mode == .terminal)
        #expect(r.via == "skipped")
        #expect(r.text == "npm test")
    }

    @Test func systemPromptIsBasePlusModeBlock() {
        let s = Prompts.system(mode: .chat)
        #expect(s.hasPrefix(Prompts.base))
        #expect(s.contains("<mode name=\"chat\">"))
        #expect(Prompts.system(mode: .codingAgent, structure: true).contains("thinking aloud"))
        #expect(!Prompts.system(mode: .codingAgent).contains("Goal:"))
        #expect(Prompts.system(mode: .codingAgent, structure: true, forced: true).contains("asked for a prompt"))
    }
}

/// The modes through the real LLMs, including two real dictations from the log.
/// ALOUD_INTEGRATION=1 GROQ_API_KEY=... ANTHROPIC_API_KEY=... swift test --filter ModesLive
/// The rows of the 2026-10-31 field test, as speech-to-text wrote them.
@Suite("Field test fixes")
struct FieldTestTests {
    @Test func correctionMarkerIgnoresPunctuationInside() {
        #expect(Prepass.hasCorrectionMarker("to Thursday because... No, wait, Friday works better."))
        #expect(Prepass.run("move it to Thursday because... No, wait, Friday works better.").needsLLM)
        #expect(!Prepass.hasCorrectionMarker("I know what's new with the waitlist"))
    }

    @Test func applyingASpokenCorrectionIsAccepted() {
        let input = "So I was thinking that we should, move the meeting to Thursday because... No, wait, Friday works better."
        let out = "So I was thinking that we should move the meeting to Friday because it works better."
        #expect(Guardrail.check(input: input, output: out, level: .light) == .accept)
    }

    @Test func hesitationBetweenCommasTakesTheCommas() {
        #expect(Prepass.run("we should, uh, move the meeting").text == "We should move the meeting")
        #expect(Prepass.run("Um, so I think").text == "So I think")
    }

    @Test func listTitleGetsItsOwnLine() {
        #expect(OutputHygiene.finish("- Grocery list: eggs\n- Milk\n- Two loaves of bread\n- Spinach", mode: .list)
                == "Grocery list:\n- Eggs\n- Milk\n- Two loaves of bread\n- Spinach")
        #expect(OutputHygiene.finish("Grocery list: eggs, milk, two loaves of bread and spinach.", mode: .list)
                == "Grocery list:\n- Eggs\n- Milk\n- Two loaves of bread\n- Spinach")
    }

    @Test func listItemsStartWithACapital() {
        #expect(OutputHygiene.finish("- eggs\n- two litres of milk", mode: .list) == "- Eggs\n- Two litres of milk")
    }

    @Test func targetAppContextLineIsDropped() {
        let t = Cleaner.dropAppOnlyContext("Goal: Fix the token refresh.\nContext: Target app is Terminal.\nConstraints: Don't touch the database.",
                                           context: AppContext(bundleID: "com.apple.Terminal", appName: "Terminal"), spoken: "fix it")
        #expect(!t.contains("Target app"))
    }

    @Test func emailGreetingAndSignOffOnTheirOwnLines() {
        #expect(OutputHygiene.finish("Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks. Shekhar.",
                                     mode: .email)
                == "Hi Sarah,\n\nJust checking in on the contract. Let me know if you need anything.\n\nThanks,\nShekhar")
        // Already laid out: unchanged.
        let done = "Hi Sarah,\n\nJust checking in.\n\nBest,\nShekhar"
        #expect(OutputHygiene.finish(done, mode: .email) == done)
        // Not a greeting or a sign-off.
        #expect(OutputHygiene.finish("Hi I wanted to ask about the contract.", mode: .email) == "Hi I wanted to ask about the contract.")
        #expect(OutputHygiene.finish("Thanks Sarah.", mode: .email) == "Thanks Sarah.")
        // Only in email.
        #expect(OutputHygiene.finish("Thanks. Shekhar.", mode: .prose) == "Thanks. Shekhar.")
    }

    @Test func chatKeepsTheTimeAsSaid() {
        #expect(OutputHygiene.finish("Yeah, that works for me. See you at 5:00.", mode: .chat) == "Yeah, that works for me. See you at 5.")
        #expect(OutputHygiene.finish("See you at 5:00 pm.", mode: .chat) == "See you at 5:00 pm.")
        #expect(OutputHygiene.finish("See you at 5:30.", mode: .chat) == "See you at 5:30.")
        #expect(OutputHygiene.finish("The meeting is at 5:00.", mode: .email) == "The meeting is at 5:00.")
    }

    @Test func chatAppsGetSlangKeyterms() {
        #expect(ModeRouter.sttKeyterms(bundleID: "net.whatsapp.WhatsApp").contains("lol"))
        #expect(ModeRouter.sttKeyterms(bundleID: "com.apple.Notes").isEmpty)
        #expect(ModeRouter.sttKeyterms(bundleID: nil).isEmpty)
    }

    @Test func codexAppIsACodingAgent() {
        #expect(ModeRouter.route("fix the flaky test", context: AppContext(bundleID: "com.openai.codex")).mode == .codingAgent)
    }

    @Test func promptShapeSortsTheSpeakersSentences() {
        let s = OutputHygiene.promptShape("The login page breaks on Safari. Fix the redirect in authCheck.ts and add a test. "
                                          + "Don't touch the database schema.")
        #expect(s == "Goal: Fix the redirect in authCheck.ts and add a test.\nContext: The login page breaks on Safari.\n"
                + "Constraints: Don't touch the database schema.")
        let q = OutputHygiene.promptShape("So, if I enable our Aloud code base, how do I actually test it in a different "
                                          + "language? Would it actually work? Can you format, give me an example?")
        #expect(q.hasPrefix("Goal: So, if I enable"))
    }

    @Test func realVoiceSessionFixes() {
        // Scribe wrote the stutter without the space.
        #expect(OutputHygiene.collapseStutters("The, the sub-sub-agent should handle it") == "The, the sub-agent should handle it")
        #expect(OutputHygiene.collapseStutters("it was so-so, bye-bye") == "it was so-so, bye-bye")
        // A doubled symbol word is a symbol, not a stutter.
        #expect(OutputHygiene.collapseStutters("NPM run test dash dash watch") == "NPM run test dash dash watch")
        #expect(OutputHygiene.finish("- To-do list email the landlord\n- Book the bike service", mode: .list)
                == "To-do list:\n- Email the landlord\n- Book the bike service")
        #expect(Cleaner.hasSpokenSymbols("Get checkout dash p fix slash auth."))
        #expect(!Cleaner.hasSpokenSymbols("Add a new line to the point of sale screen"))
    }

    @Test func spokenSymbolsInACodingAgentGoToTheModel() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>git checkout -b fix/auth</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("Git checkout dash b fix slash auth.", context: AppContext(bundleID: "com.apple.Terminal", windowTitle: "✳ Claude Code"))
        #expect(r.mode == .codingAgent)
        #expect(r.via == "groq")
    }

    @Test func shellCommandNamesAreLowercase() {
        #expect(OutputHygiene.finish("CD~/projects.", mode: .terminal) == "cd ~/projects")
        #expect(OutputHygiene.finish("Git status", mode: .terminal) == "git status")
        #expect(OutputHygiene.finish("ls -la", mode: .terminal) == "ls -la")
        #expect(OutputHygiene.finish("Deploy the app", mode: .terminal) == "Deploy the app")
    }

    /// From a real session: three asks used to land under "Goal" as one line.
    @Test func promptShapeListsSeveralAsksAsTasks() {
        let s = OutputHygiene.promptShape("Hey, what is the status on the allowed code base? Can you help me lint the code base "
                                          + "and run proper tests? Make sure that you push on the PR until CI is green.")
        #expect(s == "Goal: Hey, what is the status on the allowed code base?\n"
                + "Tasks:\n- Can you help me lint the code base and run proper tests?\n"
                + "Done when: Make sure that you push on the PR until CI is green.")
        let t = OutputHygiene.promptShape("Scan the entire allowed codebase, add more linting tasks, and run the tests. "
                                          + "Don't touch the agent folder.")
        #expect(t == "Goal: Scan the entire allowed codebase.\nTasks:\n- Add more linting tasks.\n- Run the tests.\n"
                + "Constraints: Don't touch the agent folder.")
        // A model reply that put everything under one Goal label is re-sorted, not kept as one line.
        let u = OutputHygiene.promptShape("Goal: Fix the login redirect. Add a test for it. Don't change the signup flow.")
        #expect(u == "Goal: Fix the login redirect.\nTasks:\n- Add a test for it.\nConstraints: Don't change the signup flow.")
        #expect(Cleaner.looksStructured(t))
        // Unpunctuated run-on (every model failed): still one item per ask, a constraint and a done-when.
        let v = OutputHygiene.promptShape("So I want you to scan the entire allowed code base add more linting tasks and run "
                                          + "the tests and keep going until CI is green don't touch the agent folder")
        #expect(v == "Goal: So I want you to scan the entire allowed code base add more linting tasks.\n"
                + "Tasks:\n- Run the tests.\nConstraints: Don't touch the agent folder\n"
                + "Done when: Keep going until CI is green.")
        #expect(OutputHygiene.promptShape("I don't know why the login test fails and I need it fixed")
                .hasPrefix("Goal: I don't know why the login test fails"))
    }

    @Test func promptShapeSplitsAConstraintClause() {
        #expect(OutputHygiene.promptShape("Goal: Add dark mode to the settings page and keep the existing colors as the default.")
                == "Goal: Add dark mode to the settings page.\nConstraints: Keep the existing colors as the default.")
    }

    @Test func listThatCameBackAsAParagraphGoesToTheNextModel() async {
        let groq = FakeLLM(name: "groq", reply: "<edited>To-do list: email the landlord. Book the bike service and water the plants.</edited>")
        // The correction ("fix the bike, no wait, book the bike service") is reported, as the prompt asks.
        let haiku = FakeLLM(name: "haiku", reply: "<layout>list</layout>\n<edited>To-do list:\n- Email the landlord\n- Book the bike service\n- Water the plants</edited>\n<correction>fix the bike → book the bike service</correction>")
        let r = await Cleaner(chain: [.init(groq, timeout: 1), .init(haiku, timeout: 1)])
            .clean("To-do list, email the landlord, fix the bike. No, wait, book the bike service and water the plants.")
        #expect(r.via == "haiku")
        #expect(r.text == "To-do list:\n- Email the landlord\n- Book the bike service\n- Water the plants")
    }

    @Test func modelNeverSeesHesitationSounds() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>I think what we should do now is test the agent.</edited>")
        _ = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("I think what we should really do now is, um, test the agent after the changes", context: AppContext())
        #expect(llm.calls.users.first?.contains("um,") == false)
    }

    @Test func forcedPromptIsLaidOutEvenWhenTheModelKeptAParagraph() async {
        let para = "The login page breaks on Safari. Fix the redirect in authCheck.ts and add a test. Don't touch the database schema."
        let llm = FakeLLM(name: "groq", reply: "<edited>\(para)</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("the login page breaks on safari, fix the redirect in auth check dot ts and add a test, don't touch the "
                   + "database schema, as a prompt", context: AppContext(bundleID: "com.apple.Terminal", windowTitle: "✳ claude"))
        #expect(r.restructured)
        #expect(r.text.hasPrefix("Goal: Fix the redirect"))
        #expect(r.text.contains("Constraints: Don't touch the database schema."))
    }
}

@Suite("ModesLive", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ALOUD_INTEGRATION"] == "1"))
struct ModesLiveTests {
    static let env = ProcessInfo.processInfo.environment
    static let claudeCode = AppContext(bundleID: "com.apple.Terminal", appName: "Terminal", windowTitle: "aloud — claude — 120×40")

    struct Case {
        var input: String
        var ctx: AppContext
        var mode: DictationMode
        var structured: Bool
        var must: [String] = []
        var mustNot: [String] = []
    }

    static let cases: [Case] = [
        // Thinking aloud in Claude Code: long, but not a multi-part request -> paragraphs, own words.
        Case(input: "so I've been thinking about the onboarding flow and um honestly I'm not sure the permission screen is the "
             + "problem, I think people just don't understand why we need the microphone, and maybe that's a copy issue more "
             + "than a design issue, I don't know, it's just a hunch at this point",
             ctx: claudeCode, mode: .codingAgent, structured: false,
             must: ["I'm not sure", "hunch", "copy issue"], mustNot: ["Goal:", "Requirements:"]),
        // Real dictation from the log (stutter + question to the agent).
        Case(input: "Okay, it works. So, what is the update on the research done for, by the sub- sub-agent?",
             ctx: claudeCode, mode: .codingAgent, structured: false,
             must: ["sub-agent", "research"], mustNot: ["sub-sub", "\u{2011}", "Goal:"]),
        // Real dictation from the log: a conversational request, 100+ words, used to become Goal/Requirements.
        Case(input: "Also, this very text is being typed using, um, Aloud, and I'm seeing that when I use sub- sub-agent, "
             + "it basically types sub twice. So can that also be added? Can this task be added to the list that we need to "
             + "clean the output which is being presented in the text app? Apparently, that text which is supposed to be "
             + "displayed needs to be, like, really clean. So maybe, like, a post-processing from the backend LLM could be "
             + "used here. So please add that to the design doc or whatever scratchpad you have created, and, uh, we will do, "
             + "like, research",
             ctx: claudeCode, mode: .codingAgent, structured: false,
             must: ["twice", "design doc", "scratchpad"], mustNot: ["sub-sub", "\u{2011}", "\u{201C}"]),
        // Instruction-shaped dictation in Notes: cleaned, never answered.
        Case(input: "can you write me a python function that um reverses a linked list", ctx: AppContext(bundleID: "com.apple.Notes"),
             mode: .prose, structured: false, must: ["linked list"], mustNot: ["def ", "```"]),
        Case(input: "grocery list eggs two litres of milk uh some spinach and a loaf of sourdough",
             ctx: AppContext(bundleID: "com.apple.Notes"), mode: .list, structured: true,
             must: ["- ", "milk", "spinach", "sourdough"]),
        Case(input: "hi priya comma thanks for sending the deck over um I'll take a look tonight and get back to you tomorrow best shekhar",
             ctx: AppContext(bundleID: "com.apple.mail"), mode: .email, structured: false,
             must: ["Priya", "tonight", "Shekhar"], mustNot: ["Dear", "I hope this"]),
        Case(input: "lol yeah ill push it tonight dont worry", ctx: AppContext(bundleID: "com.tinyspeck.slackmacgap"),
             mode: .chat, structured: false, must: ["push it tonight"]),
        // Field test 2026-10-31, as speech-to-text wrote them.
        Case(input: "Um, so I was thinking that we should, uh, move the meeting to Thursday because... No, wait, Friday works better.",
             ctx: AppContext(bundleID: "com.apple.Notes"), mode: .prose, structured: false,
             must: ["Friday"], mustNot: ["Thursday", "No, wait", "should,"]),
        Case(input: "Hi Sarah, just checking in on the contract. Let me know if you need anything. Thanks, Shekhar.",
             ctx: AppContext(bundleID: "com.google.Chrome", windowTitle: "Compose Mail - Gmail"), mode: .email, structured: false,
             must: ["Hi Sarah,\n\n", "\n\nThanks,\nShekhar"]),
        Case(input: "git checkout dash b fix slash auth", ctx: AppContext(bundleID: "com.apple.Terminal", windowTitle: "-zsh"),
             mode: .terminal, structured: false, must: ["git checkout -b fix/auth"], mustNot: ["."]),
    ]

    static func run(_ chain: [CleanupLLM]) async {
        let c = Cleaner(chain: chain.map { .init($0, timeout: 1.5) })
        let clock = ContinuousClock()
        for k in cases {
            let t0 = clock.now
            let r = await c.clean(k.input, context: k.ctx)
            print("--- \(k.mode) via \(r.via) in \(clock.now - t0) \(r.notes.filter { $0.contains("rejected") || $0.contains("failed") })\n\(r.text)")
            #expect(r.mode == k.mode)
            #expect(r.via != "fallback", "\(r.notes)")
            #expect(r.restructured == k.structured, "\(r.text)")
            for m in k.must { #expect(r.text.lowercased().contains(m.lowercased()), "missing \(m): \(r.text)") }
            for m in k.mustNot { #expect(!r.text.contains(m), "has \(m): \(r.text)") }
        }
    }

    @Test(.enabled(if: env["GROQ_API_KEY"] != nil && env["ANTHROPIC_API_KEY"] != nil)) func productionChain() async {
        await Self.run([OpenAICompatibleLLM.groq(apiKey: Self.env["GROQ_API_KEY"]!),
                        AnthropicLLM(apiKey: Self.env["ANTHROPIC_API_KEY"]!)])
    }

    @Test(.enabled(if: env["GROQ_API_KEY"] != nil)) func groqAlone() async {
        await Self.run([OpenAICompatibleLLM.groq(apiKey: Self.env["GROQ_API_KEY"]!)])
    }

    @Test(.enabled(if: env["ANTHROPIC_API_KEY"] != nil)) func haikuAlone() async {
        await Self.run([AnthropicLLM(apiKey: Self.env["ANTHROPIC_API_KEY"]!)])
    }
}

@Suite("Negation spelling")
struct NegationSpellingTests {
    @Test func apostropheLessNegationsCount() {
        #expect(Fidelity.negations("lol yeah ill push it tonight dont worry") == 1)
        #expect(Fidelity.negations("Lol yeah, I'll push it tonight, don't worry.") == 1)
        #expect(Fidelity.negations("I want to print the client list") == 0)
    }
}

/// From a real WhatsApp session: "Grocery list" came back as the first bullet, and a list with
/// hesitations lost its title and a comma.
@Suite("Grocery list fixes")
struct GroceryListTests {
    @Test func listNameOnItsOwnBulletBecomesTheTitle() {
        #expect(OutputHygiene.finish("- Grocery list\n- Eggs\n- Bacon\n- Milk\n- Meatloaf", mode: .list)
                == "Grocery list:\n- Eggs\n- Bacon\n- Milk\n- Meatloaf")
    }

    @Test func hesitationBetweenListItemsKeepsOneComma() {
        #expect(Prepass.run("Grocery list. Uh, I need eggs, uh, meatloaf, bread loaf, and pasta.").text
                == "Grocery list. I need eggs, meatloaf, bread loaf, and pasta.")
        #expect(Prepass.run("We should, uh, move the launch.").text == "We should move the launch.")
    }

    @Test func missingListNameIsPutBack() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>- Eggs\n- Meatloaf\n- Bread loaf\n- Pasta</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("Grocery list. Uh, I need eggs, uh, meatloaf, bread loaf, and pasta.", context: AppContext(bundleID: "net.whatsapp.WhatsApp"))
        #expect(r.via == "groq", "\(r.notes)")
        #expect(r.text == "Grocery list:\n- Eggs\n- Meatloaf\n- Bread loaf\n- Pasta")
    }
}

/// From a real session: free speech in Claude Code was laid out as a prompt and lost its last words,
/// because it ended with "... that this is XYZ as a prompt".
@Suite("Prompt or free speech")
struct PromptOrFreeSpeechTests {
    @Test func talkingAboutTheCueIsNotTheCue() {
        let said = "I do not want to explicitly tell the system that this is XYZ as a prompt."
        let r = ModeRouter.route(said, context: AppContext(bundleID: "com.apple.Terminal", windowTitle: "✳ claude"))
        #expect(!r.forceStructure)
        #expect(r.transcript.hasSuffix("as a prompt."))
        #expect(ModeRouter.route("fix the login bug and add a test, as a prompt", context: AppContext()).forceStructure)
        #expect(ModeRouter.route("fix the login bug as a prompt", context: AppContext()).forceStructure)
    }

    @Test func mediumCodingDictationsGoToTheModelToDecide() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>Goal: Fix the redirect in the login handler.\nConstraints: Don't touch the signup form or the session code, please.</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean(
            "fix the redirect in the login handler and don't touch the signup form or the session code please",
            context: AppContext(bundleID: "com.apple.Terminal", windowTitle: "✳ claude"))
        #expect(r.via == "groq")
        #expect(r.restructured)
    }

    /// Free speech kept as sentences gets light cleanup's strict checks: dropping words is rejected.
    @Test func freeSpeechKeptAsSentencesIsHeldToLightChecks() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>The build is faster. The settings page flickers.</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean(
            "so I tried the new build this morning and the login felt a lot faster but the settings page still flickers when you switch tabs",
            context: AppContext(bundleID: "com.apple.Terminal", windowTitle: "✳ claude"))
        #expect(r.via == "fallback")
    }

    @Test func repairLeavesNamesTheRecognizerChose() {
        let r = RecognitionRepair.apply([.init(heard: "Aloud", meant: "Claude")], to: "I used Aloud, and then interacted with Claude CLI.")
        #expect(r.text == "I used Aloud, and then interacted with Claude CLI.")
        #expect(r.notes == ["repair refused: Aloud -> Claude (name)"])
        // Lowercase misrecognitions are still fixed, and so is a capitalized first word.
        #expect(RecognitionRepair.apply([.init(heard: "get hub", meant: "GitHub")], to: "Push it to get hub.").text == "Push it to GitHub.")
        #expect(RecognitionRepair.apply([.init(heard: "Poll request", meant: "Pull request")], to: "Poll request is ready.").text
                == "Pull request is ready.")
    }

    @Test func listNameInTheOpeningSentenceBecomesTheTitle() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>- Eggs\n- Bacon\n- Bread</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("Create a grocery list for me. Uh, eggs, bacon, bread.", context: AppContext(bundleID: "net.whatsapp.WhatsApp"))
        #expect(r.text == "Grocery list:\n- Eggs\n- Bacon\n- Bread")
    }
}

@Suite("List or sentences in other apps")
struct LayoutChoiceTests {
    @Test func shortTextReachesTheModel() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>Passport, charger and boots.</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean("Passport, charger and boots.", context: AppContext(bundleID: "com.apple.Notes"))
        #expect(r.via == "groq")
    }

    /// A list chosen in Notes is checked with the structure rules (it drops "and"), and shaped.
    @Test func aListChosenInNotesIsAccepted() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>Things to pack:\n- passport\n- charger\n- sunscreen\n- hiking boots</edited>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)])
            .clean("Things to pack, passport, charger, sunscreen and hiking boots.", context: AppContext(bundleID: "com.apple.Notes"))
        #expect(r.via == "groq", "\(r.notes)")
        #expect(r.restructured)
        #expect(r.text == "Things to pack:\n- Passport\n- Charger\n- Sunscreen\n- Hiking boots")
    }
}

@Suite("Goal with several asks")
struct GoalAsksTests {
    @Test func severalAsksInTheGoalBecomeTasks() {
        #expect(OutputHygiene.splitGoalAsks("Goal: Scan the entire allowed code base, add more linting tasks, and run the tests.\nConstraints: Don't touch the agent folder.\nDone when: CI is green.")
                == "Goal: Scan the entire allowed code base.\nTasks:\n- Add more linting tasks.\n- Run the tests.\nConstraints: Don't touch the agent folder.\nDone when: CI is green.")
        // One ask, or a Tasks section already there: unchanged.
        let one = "Goal: Fix the redirect in the login handler.\nConstraints: Don't touch the signup form."
        #expect(OutputHygiene.splitGoalAsks(one) == one)
        let has = "Goal: Check the service, add a lint step.\nTasks:\n- Scan imports."
        #expect(OutputHygiene.splitGoalAsks(has) == has)
    }
}

/// From a real WhatsApp dictation: "Let's do 7. No, let's do 8." Both models applied the correction
/// and the guardrail rejected them for dropping "7" and "no", so the uncorrected text was typed.
@Suite("Model-reported corrections")
struct ReportedCorrectionTests {
    static let heard = "Hey, are we on for dinner tonight? Let's do 7:00. No, um, let's do 8:00."

    @Test func theReportIsReadFromTheReply() {
        let (rest, cs) = OutputHygiene.extractCorrections("<edited>Let's do 8.</edited>\n<correction>7:00 → 8:00</correction>")
        #expect(rest.trimmingCharacters(in: .whitespacesAndNewlines) == "<edited>Let's do 8.</edited>")
        #expect(cs.count == 1 && cs[0].from == "7:00" && cs[0].to == "8:00")
    }

    /// From a real WhatsApp dictation: the model applied the correction and, without a way to say
    /// so, was rejected for dropping "7" and "no".
    @Test func aReportedCorrectionIsAccepted() async {
        let llm = FakeLLM(name: "groq", reply: "<edited>Hey, are we on for dinner tonight? Let's do 8.</edited>\n<correction>7:00 → 8:00</correction>")
        let r = await Cleaner(chain: [.init(llm, timeout: 1)]).clean(Self.heard, context: AppContext(bundleID: "net.whatsapp.WhatsApp"))
        #expect(r.via == "groq", "\(r.notes)")
        #expect(r.text == "Hey, are we on for dinner tonight? Let's do 8.")
        #expect(r.notes.contains("groq correction: 7:00 -> 8:00"))
    }

    @Test func aReportThatDoesNotCheckOutIsNotTrusted() {
        let input = "Can you get me something from the store? Pizza. No, pastry."
        // Replaced words still in the output, a replacement nobody said, or nothing reported.
        #expect(!Guardrail.verifies([("pizza", "pastry")], input: input, output: "Can you get me pizza and pastry?"))
        #expect(!Guardrail.verifies([("pizza", "cake")], input: input, output: "Can you get me cake?"))
        #expect(!Guardrail.verifies([], input: input, output: "Can you get me pastry?"))
        #expect(Guardrail.verifies([("Pizza", "pastry")], input: input, output: "Can you get me a pastry from the store?"))
        // An extension replaces nothing, so it checks out as long as both parts were said.
        #expect(Guardrail.verifies([("the team", "the whole design team")], input: "share it with the team, the whole design team",
                                   output: "Share it with the whole design team."))
        // A report can't excuse dropping other words: "store" is gone too, and that's not a correction.
        #expect(Guardrail.check(input: "Please buy the tickets for the concert in Berlin tomorrow. Pizza. No, pastry.",
                                output: "Please buy pastry.", level: .light, corrections: [("Pizza", "pastry")]) != .accept)
    }
}
