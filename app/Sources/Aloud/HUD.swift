import AppKit
import AgentUI
import AloudCore
import AudioKit
import HotkeyKit
import SwiftUI

/// The small floating pill near the bottom of the screen. It is a non-activating panel, so showing it
/// never steals focus from the app you're dictating into.
///
/// While you talk it shows a live waveform driven by the microphone level: bars that rise and fall
/// with your voice and settle to a slow breathing when you pause, so it's obvious the mic is open
/// and hearing you (research/08-agent-ui: "show that it's listening, not just that it's on").
@MainActor
final class HUD {
    /// Set once the recorder exists; read every frame while listening.
    var meter: LevelMeter?

    private let panel: NSPanel
    private let model = ListeningHUDModel()
    private let host: NSHostingView<ListeningHUDView>
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // the pill draws its own, a window shadow would be rectangular
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        host = NSHostingView(rootView: ListeningHUDView(model: model, level: { 0 }))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
    }

    func show(_ status: SessionStatus) {
        hideTask?.cancel()
        switch status {
        case .idle:
            panel.orderOut(nil)
            return
        case .listening(let mode): model.phase = .listening(Self.kind(mode))
        case .transcribing: model.phase = .transcribing
        case .inserted: model.phase = .inserted
        case .failed(let msg): model.phase = .message(msg, failed: true)
        }
        present()
        switch status {
        case .inserted: hide(after: .milliseconds(700))
        case .failed: hide(after: .seconds(3))
        default: break
        }
    }

    /// A transient status line (agent progress etc.) that isn't a dictation state.
    func showMessage(_ text: String, for duration: Duration = .seconds(3)) {
        hideTask?.cancel()
        model.phase = .message(text, failed: false)
        present()
        hide(after: duration)
    }

    private func present() {
        let meter = self.meter
        host.rootView = ListeningHUDView(model: model, level: { meter?.value ?? 0 })
        position()
        panel.orderFrontRegardless()
    }

    static func kind(_ mode: RecordingMode) -> ListeningHUDModel.Kind {
        switch mode {
        case .dictation: return .dictation
        case .task: return .task
        case .command: return .command
        }
    }

    private func hide(after delay: Duration) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + 56, width: size.width, height: size.height),
                       display: true)
    }
}
