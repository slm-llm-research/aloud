import AppKit

/// Native editor for the agent's allowed folders (instead of hand-editing agent.json). Changes are
/// written to agent.json, keeping any other settings in it, and the agent restarts to apply them.
@MainActor
final class AgentSettingsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onSave: (() -> Void)?

    private let configURL: URL
    private var folders: [String] = []
    private var window: NSWindow?
    private let table = NSTableView()
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    init(configURL: URL) {
        self.configURL = configURL
    }

    func show() {
        folders = AgentSettings.load(configURL).allowedRoots
        if window == nil { build() }
        table.reloadData()
        updateButtons()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
                         styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.title = "Agent Settings"
        w.isReleasedWhenClosed = false

        let intro = NSTextField(wrappingLabelWithString:
            "The agent can only read, change and run commands inside these folders. "
            + "Anything outside them is blocked, even if you approve it.")
        intro.font = .systemFont(ofSize: 12)

        let column = NSTableColumn(identifier: .init("folder"))
        column.title = "Allowed folders"
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let add = NSButton(title: "Add Folder…", target: self, action: #selector(addFolder))
        removeButton.target = self
        removeButton.action = #selector(removeFolder)
        let done = NSButton(title: "Done", target: w, action: #selector(NSWindow.performClose(_:)))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [add, removeButton, NSView(), done])

        let stack = NSStackView(views: [intro, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        w.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            intro.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        window = w
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Allow"
        panel.message = "Choose folders the agent may work in"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        guard let window, panel.runModal() == .OK else { return }
        var changed = false
        for url in panel.urls {
            let display = AgentSettings.abbreviate(url.path)
            if !folders.contains(display) {
                folders.append(display)
                changed = true
            }
        }
        if changed { save() }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func removeFolder() {
        let row = table.selectedRow
        guard row >= 0, row < folders.count else { return }
        folders.remove(at: row)
        save()
    }

    private func save() {
        AgentSettings.save(allowedRoots: folders, to: configURL)
        table.reloadData()
        updateButtons()
        onSave?()
    }

    private func updateButtons() {
        removeButton.isEnabled = table.selectedRow >= 0 && folders.count > 1  // keep at least one
    }

    func numberOfRows(in tableView: NSTableView) -> Int { folders.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: folders[row])
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
}

/// Reads/writes agent.json without disturbing settings this window doesn't manage.
enum AgentSettings {
    struct Values { var allowedRoots: [String] }

    static func load(_ url: URL) -> Values {
        let obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        return Values(allowedRoots: obj["allowedRoots"] as? [String] ?? ["~/Documents/MLEngineering"])
    }

    static func save(allowedRoots: [String], to url: URL) {
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        obj["allowedRoots"] = allowedRoots
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
