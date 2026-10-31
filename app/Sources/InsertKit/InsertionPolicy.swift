import Foundation

/// How text gets into the focused app (PLAN.md §6).
public enum InsertionStrategy: Equatable, Sendable {
    /// Put the text on the pasteboard and synthesize Cmd-V. Works almost everywhere.
    case pasteShortcut
    /// Type the text as Unicode key events. For remote desktops / VMs, where Cmd-V arrives as "v".
    case typeUnicode
    /// Don't insert: copy to the clipboard and tell the user (secure input / password fields).
    case clipboardOnly
}

public enum AppCategory: Equatable, Sendable {
    case terminal, remoteDesktop, other
}

public enum InsertionPolicy {
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
    ]
    static let remoteDesktops: Set<String> = [
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.parsec.www",
        "com.vmware.fusion", "com.parallels.desktop.console", "com.utmapp.UTM",
    ]

    public static func category(bundleID: String?) -> AppCategory {
        guard let id = bundleID else { return .other }
        if terminals.contains(id) { return .terminal }
        if remoteDesktops.contains(id) { return .remoteDesktop }
        return .other
    }

    public static func strategy(bundleID: String?, secureInputActive: Bool) -> InsertionStrategy {
        if secureInputActive { return .clipboardOnly }
        switch category(bundleID: bundleID) {
        case .remoteDesktop: return .typeUnicode
        case .terminal, .other: return .pasteShortcut
        }
    }

    /// Text safe to put into the target. In terminals a trailing newline would *run* the command and
    /// control characters can do odd things, so both are removed. Elsewhere only trims edges.
    public static func sanitize(_ text: String, for category: AppCategory) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if category == .terminal {
            t = String(t.unicodeScalars.filter { s in
                s == "\n" || s == "\t" || !(s.properties.generalCategory == .control)
            })
            while t.hasSuffix("\n") { t.removeLast() }
        }
        return t
    }
}
