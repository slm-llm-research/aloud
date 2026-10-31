import AppKit
import ApplicationServices
import InstructFlowCore

/// Reads the frontmost app and its focused window's title via Accessibility. Editors put the open
/// file and project in the title ("auth.ts — api-server"), terminals the running command.
enum FocusedApp {
    @MainActor
    static func current() -> DictationContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return DictationContext() }
        return DictationContext(bundleID: app.bundleIdentifier, appName: app.localizedName,
                                windowTitle: windowTitle(pid: app.processIdentifier))
    }

    static func windowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        // Don't let a hung app stall the dictation.
        AXUIElementSetMessagingTimeout(appElement, 0.05)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }
}
