import SwiftUI

/// The dictation pill's content (the panel lives in the app's HUD). While you talk it shows a live
/// waveform driven by the microphone level: bars that rise and fall with your voice and settle to a
/// slow breathing in pauses, so it's obvious the mic is open and hearing you.
/// What the listening pill shows; the app sets `phase`, the view animates.
@MainActor @Observable
public final class ListeningHUDModel {
    public enum Kind: Equatable, Sendable { case dictation, task, command }
    public enum Phase: Equatable {
        case listening(Kind)
        case transcribing
        case inserted
        case message(String, failed: Bool)
    }
    public var phase: Phase = .transcribing
    public init() {}
}

public struct ListeningHUDView: View {
    let model: ListeningHUDModel
    let level: () -> Float

    public init(model: ListeningHUDModel, level: @escaping () -> Float) {
        self.model = model
        self.level = level
    }

    public var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .listening(let mode):
                Waveform(level: level, color: Self.tint(mode), active: true)
                Text(Self.label(mode)).foregroundStyle(.primary)
            case .transcribing:
                Waveform(level: { 0 }, color: .white, active: false)
                Text("Transcribing").foregroundStyle(.secondary)
            case .inserted:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Done").foregroundStyle(.secondary)
            case .message(let text, let failed):
                if failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                Text(text).lineLimit(2).frame(maxWidth: 380, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minWidth: 150)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .padding(10)  // room for the shadow inside the window
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    static func label(_ mode: ListeningHUDModel.Kind) -> String {
        switch mode {
        case .dictation: return "Listening"
        case .task: return "Agent listening"
        case .command: return "Listening for an edit"
        }
    }

    /// Dictation white, agent tasks orange (the same accent the agent island uses), edits blue.
    static func tint(_ mode: ListeningHUDModel.Kind) -> Color {
        switch mode {
        case .dictation: return .white
        case .task: return .orange
        case .command: return .cyan
        }
    }
}

/// Bars that follow the voice. Each bar gets its own share of the level and its own wobble, so it
/// reads like a live audio meter rather than one block moving up and down. With `active == false`
/// (transcribing) a soft highlight sweeps across low bars instead: busy, but not hearing.
struct Waveform: View {
    let level: () -> Float
    let color: Color
    let active: Bool

    static let bars = 9
    /// Louder in the middle, like a voice-memo meter.
    static let envelope: [Double] = [0.45, 0.62, 0.8, 0.94, 1, 0.94, 0.8, 0.62, 0.45]
    @State private var smoothed = Smoothed()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let v = active ? smoothed.next(Double(level())) : 0
                let barW: CGFloat = 3
                let gap = (size.width - CGFloat(Self.bars) * barW) / CGFloat(Self.bars - 1)
                for i in 0..<Self.bars {
                    let phase = Double(i) * 0.9
                    var h: Double
                    var alpha = 1.0
                    if active {
                        // Breathing floor (mic open, quiet) plus the voice, each bar slightly out of step.
                        let breathe = 0.16 + 0.06 * sin(t * 2.4 + phase)
                        let wobble = 0.75 + 0.25 * sin(t * 13 + phase * 1.7)
                        h = breathe + v * Self.envelope[i] * wobble * 0.84
                    } else {
                        let sweep = (sin(t * 5 - phase * 0.7) + 1) / 2
                        h = 0.18 + 0.14 * sweep
                        alpha = 0.35 + 0.55 * sweep
                    }
                    let barH = max(barW, CGFloat(min(1, h)) * size.height)
                    let rect = CGRect(x: CGFloat(i) * (barW + gap), y: (size.height - barH) / 2, width: barW, height: barH)
                    gc.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(color.opacity(alpha)))
                }
            }
        }
        .frame(width: 44, height: 20)
        .accessibilityHidden(true)
    }

    /// Fast attack, slower release: words pop, pauses fade instead of snapping to the floor.
    final class Smoothed {
        private var value = 0.0
        func next(_ target: Double) -> Double {
            value += (target - value) * (target > value ? 0.45 : 0.12)
            return value
        }
    }
}
