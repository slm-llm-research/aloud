import AppKit
import AudioKit
import CleanupKit
import HotkeyKit
import InsertKit
import AloudCore
import STTKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hud = HUD()
    private let parakeet = ParakeetTranscriber()
    private let scribe = ScribeProvider()
    private let cleaner = CleanerBox()
    private var agent: AgentController!
    private lazy var agentSettings: AgentSettingsWindow = {
        let w = AgentSettingsWindow(configURL: AgentController.configURL)
        w.onSave = { [weak self] in self?.agent.restart() }
        return w
    }()
    private var session: Session!
    private var tap: EventTap?
    private var modelReady = false
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let listenerLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let keysLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let agentLine = NSMenuItem(title: "Agent: off", action: nil, keyEquivalent: "")
    private let lastLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tasksItem = NSMenuItem(title: "Agent Tasks", action: nil, keyEquivalent: "")
    private let offlineItem = NSMenuItem(title: "Offline mode (local only, no cleanup)", action: #selector(toggleOffline),
                                         keyEquivalent: "")
    private let cleanupItem = NSMenuItem(title: "AI cleanup", action: #selector(toggleCleanup), keyEquivalent: "")

    private var offline: Bool {
        get { UserDefaults.standard.bool(forKey: "offline") }
        set { UserDefaults.standard.set(newValue, forKey: "offline") }
    }
    private var cleanupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cleanup") }
    }

    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Aloud")
    static let dictionaryURL = supportDir.appendingPathComponent("dictionary.txt")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First launch after a rename (InstructFlow, earlier Murmur): bring keys, dictionary, agent
        // folders and the agent audit log (Task Center history) along. Logs go first, before
        // dlog creates the new log folder.
        let home = FileManager.default.homeDirectoryForCurrentUser
        var migrated: [String] = []
        for sub in ["Library/Logs", "Library/Application Support"] {
            for legacy in ["InstructFlow", "Murmur"] {
                let copied = (try? DataMigration.migrate(from: home.appendingPathComponent("\(sub)/\(legacy)"),
                                                         to: home.appendingPathComponent("\(sub)/Aloud"))) ?? []
                migrated += copied.map { "\(legacy)/\($0)" }
            }
        }
        if !migrated.isEmpty { dlog("migrated: \(migrated.joined(separator: ", "))") }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Aloud")
        let menu = NSMenu()
        menu.delegate = self
        for item in [statusLine, listenerLine, keysLine, agentLine, lastLine] { menu.addItem(item) }
        tasksItem.submenu = NSMenu()
        lastLine.isHidden = true
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hold Right Shift to dictate · double-tap to latch", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Right Shift + Right ⌘: give the agent a task", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(tasksItem)
        let center = NSMenuItem(title: "Task Center…", action: #selector(openTaskCenter), keyEquivalent: "t")
        center.target = self
        menu.addItem(center)
        menu.addItem(NSMenuItem(title: "Stop All Agent Tasks", action: #selector(stopAgents), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Agent Settings…", action: #selector(editAgentSettings),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Agent Audit Log", action: #selector(openAudit), keyEquivalent: ""))
        menu.addItem(.separator())
        offlineItem.target = self
        cleanupItem.target = self
        menu.addItem(cleanupItem)
        menu.addItem(offlineItem)
        menu.addItem(NSMenuItem(title: "Edit Dictionary…", action: #selector(editDictionary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Import API Keys from .env…", action: #selector(importKeys), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Permissions…", action: #selector(showPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Aloud", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        agent = AgentController(hud: hud)
        agent.onChange = { [weak self] in self?.refreshMenu() }
        session = Session(audio: AudioRecorder(), transcriber: ParakeetAdapter(engine: parakeet),
                          inserter: TextInserter(), streaming: scribe, cleaner: cleaner, tasks: agent,
                          contextProvider: { FocusedApp.current() })
        session.onStatus = { [weak self] status in
            if case .inserted = status {} else { dlog("status: \(status)") }
            self?.hud.show(status)
        }
        session.onCompleted = { [weak self] e in
            let ms = { (d: Duration) in Int((Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18) * 1000) }
            dlog("done: mode=\(e.mode) audio=\(String(format: "%.1f", e.audioSeconds))s stt=\(e.sttSource.rawValue) "
                 + "sttLatency=\(ms(e.sttLatency))ms total=\(ms(e.latency))ms app=\(e.context.bundleID ?? "?") "
                 + "cleanup=\(e.cleanupVia)" + (e.sttNotes.isEmpty ? "" : " scribe: \(e.sttNotes)") + "\n"
                 + "    heard: \(e.rawTranscript)\n    typed: \(e.transcript)")
            DictationRecord.append([
                "ts": Date().timeIntervalSince1970, "mode": "\(e.mode)", "app": e.context.bundleID ?? "",
                "title": e.context.windowTitle ?? "", "heard": e.rawTranscript, "typed": e.transcript,
                "stt": e.sttSource.rawValue, "cleanup": e.cleanupVia, "audio_s": e.audioSeconds,
                "stt_ms": ms(e.sttLatency), "total_ms": ms(e.latency), "stt_notes": e.sttNotes,
            ])
            self?.lastLine.title = "Last: \(ms(e.latency)) ms (\(e.sttSource.rawValue) speech, cleanup: "
                + "\(e.cleanupVia.split(separator: " ").first ?? "none"))"
            self?.lastLine.isHidden = false
        }

        ensureDictionaryFile()
        reconfigure()
        let p = Permissions.current()
        dlog("launch: mic=\(p.microphone) accessibility=\(p.accessibility) inputMonitoring=\(p.inputMonitoring) keys: \(KeyStore.summary)")
        refreshMenu()
        agent.start()
        Task { await start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agent.shutdown()
    }

    @objc private func stopAgents() { agent.stopAll() }

    @objc private func editAgentSettings() {
        agentSettings.show()
    }

    @objc private func openAudit() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Aloud/agent-audit.jsonl")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    /// Rebuilds the cloud STT + cleanup configuration from keys, dictionary and toggles.
    private func reconfigure() {
        let dict = PersonalDictionary.parse((try? String(contentsOf: Self.dictionaryURL, encoding: .utf8)) ?? "")
        scribe.configure(apiKey: KeyStore.get("ELEVENLABS_API_KEY"), keyterms: dict.keyterms(), enabled: !offline)

        var chain: [Cleaner.Step] = []
        if !offline, cleanupEnabled {
            if let k = KeyStore.get("GROQ_API_KEY") { chain.append(.init(OpenAICompatibleLLM.groq(apiKey: k), timeout: 1.5)) }
            if let k = KeyStore.get("ANTHROPIC_API_KEY") { chain.append(.init(AnthropicLLM(apiKey: k), timeout: 2.5)) }
        }
        cleaner.set(Cleaner(chain: chain, dictionary: dict))
        dlog("config: offline=\(offline) cleanup=\(cleanupEnabled) llms=\(chain.map(\.llm.name)) dictionary=\(dict.terms.count) terms/\(dict.replacements.count) fixes")
    }

    private func start() async {
        await Permissions.requestMissing()
        startTapIfPossible()
        statusLine.title = "Loading speech model…"
        do {
            try await parakeet.prepare()
            _ = try? await parakeet.transcribe([Float](repeating: 0, count: 16_000))  // warm-up
            modelReady = true
            dlog("speech model ready")
        } catch {
            dlog("model load failed: \(error)")
            statusLine.title = "Speech model failed to load"
            return
        }
        refreshMenu()
    }

    private func startTapIfPossible() {
        guard tap == nil else { return }
        let t = EventTap(observer: { input, output in
            // Only trigger-related events; ordinary typing is not logged.
            switch input {
            case .keyDown(.other, _), .keyUp: return
            default: dlog("key: \(input) -> \(output.actions) \(output.disposition)")
            }
        }, onAction: { [weak self] action in
            Task { @MainActor in self?.session.handle(action) }
        })
        if t.start() {
            tap = t
            dlog("key listener started")
        } else {
            dlog("key listener unavailable (permissions?); retrying")
            Task {
                try? await Task.sleep(for: .seconds(2))
                startTapIfPossible()
            }
        }
        refreshMenu()
    }

    private func refreshMenu() {
        if modelReady { statusLine.title = tap == nil ? "Needs permissions — see Permissions…" : "Ready" }
        listenerLine.title = tap.map { "Key listener: on (\($0.eventsSeen) key events seen)" } ?? "Key listener: off"
        keysLine.title = "Keys: \(KeyStore.summary)"
        agentLine.title = agent?.statusText ?? "Agent: off"
        refreshTasks()
        offlineItem.state = offline ? .on : .off
        cleanupItem.state = cleanupEnabled ? .on : .off
    }

    /// Recent agent tasks, newest first; choosing one opens it in the Task Center.
    private func refreshTasks() {
        guard let sub = tasksItem.submenu else { return }
        sub.removeAllItems()
        let tasks = agent?.store.tasks ?? []
        let waiting = tasks.filter { $0.state == .waiting }.count
        tasksItem.title = waiting > 0 ? "Agent Tasks (\(waiting) need you)" : "Agent Tasks"
        if tasks.isEmpty {
            sub.addItem(NSMenuItem(title: "No tasks yet: hold Right Shift + Right ⌘ and speak", action: nil, keyEquivalent: ""))
            return
        }
        let open = NSMenuItem(title: "Open Task Center…", action: #selector(openTaskCenter), keyEquivalent: "")
        open.target = self
        sub.addItem(open)
        sub.addItem(.separator())
        for t in tasks.prefix(10) {
            let glyph: String
            switch t.state {
            case .running: glyph = "◐"
            case .waiting: glyph = "⚠"
            case .done: glyph = "✓"
            case .failed: glyph = "✕"
            case .stopped: glyph = "■"
            case .interrupted: glyph = "‖"
            }
            let what = t.heard.isEmpty ? t.currentActivity : t.heard
            let detail = t.isActive ? t.currentActivity : t.summary
            let item = NSMenuItem(title: "\(glyph) \(String(what.prefix(60)))", action: #selector(showTask(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
            item.toolTip = detail
            sub.addItem(item)
        }
    }

    @objc private func showTask(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { agent.center.show(select: id) }
    }

    @objc private func openTaskCenter() { agent.center.show() }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    @objc private func toggleOffline() {
        offline.toggle()
        reconfigure()
        refreshMenu()
    }

    @objc private func toggleCleanup() {
        cleanupEnabled.toggle()
        reconfigure()
        refreshMenu()
    }

    private func ensureDictionaryFile() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: Self.dictionaryURL.path) else { return }
        let starter = """
        # Aloud personal dictionary. Changes apply when you save and click Edit Dictionary… again,
        # or on next launch.
        #
        # A plain line is a term to always spell exactly (sent to the recognizer and the cleanup AI):
        Claude Code
        Cursor
        FastAPI
        pytest
        TypeScript
        GitHub
        #
        # "heard -> written" fixes a word the recognizer keeps getting wrong:
        cload code -> Claude Code
        fast appy -> FastAPI

        """
        try? starter.write(to: Self.dictionaryURL, atomically: true, encoding: .utf8)
    }

    @objc private func editDictionary() {
        reconfigure()  // pick up edits made since the last open
        NSWorkspace.shared.open(Self.dictionaryURL)
    }

    @objc private func importKeys() {
        let panel = NSOpenPanel()
        panel.message = "Choose a .env file with ELEVENLABS_API_KEY, GROQ_API_KEY and/or ANTHROPIC_API_KEY"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let env = EnvFile.parse(text).filter { KeyStore.names.contains($0.key) }
        let imported = KeyStore.set(env) ? env.keys.sorted() : []
        dlog("imported keys: \(imported)")
        reconfigure()
        refreshMenu()
        let alert = NSAlert()
        alert.messageText = imported.isEmpty ? "No keys found" : "Imported \(imported.count) key(s)"
        alert.informativeText = KeyStore.summary
        alert.runModal()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(DiagLog.shared.url)
    }

    @objc private func showPermissions() {
        let p = Permissions.current()
        let alert = NSAlert()
        alert.messageText = "Aloud permissions"
        alert.informativeText = """
        Microphone: \(p.microphone ? "✓" : "✗  (to hear you)")
        Accessibility: \(p.accessibility ? "✓" : "✗  (to type into apps)")
        Input Monitoring: \(p.inputMonitoring ? "✓" : "✗  (to see Right Shift)")

        Grant missing ones in System Settings → Privacy & Security.
        """
        alert.addButton(withTitle: "Open Accessibility")
        alert.addButton(withTitle: "Open Input Monitoring")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: Permissions.openSettings("Privacy_Accessibility")
        case .alertSecondButtonReturn: Permissions.openSettings("Privacy_ListenEvent")
        default: break
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
