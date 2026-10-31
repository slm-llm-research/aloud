import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

/// The three macOS permissions InstructFlow needs (PLAN.md §6).
enum Permissions {
    struct Status {
        var microphone: Bool
        var accessibility: Bool
        var inputMonitoring: Bool
        var allGranted: Bool { microphone && accessibility && inputMonitoring }
    }

    static func current() -> Status {
        Status(microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               accessibility: AXIsProcessTrusted(),
               inputMonitoring: CGPreflightListenEventAccess())
    }

    /// Triggers each system prompt that hasn't been answered yet.
    static func requestMissing() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if !AXIsProcessTrusted() {
            // The value of kAXTrustedCheckOptionPrompt; the global itself isn't concurrency-safe in Swift 6.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    static func openSettings(_ pane: String) {
        // e.g. "Privacy_Accessibility", "Privacy_ListenEvent", "Privacy_Microphone"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
