import Foundation
import Testing
@testable import CleanupKit

/// Runs the cleanup over the behavior dataset (bench/behavior) and writes what would have been typed.
/// Not a pass/fail test: `bench/behavior_eval.py` scores the output. Driven by environment:
///   ALOUD_BEHAVIOR_IN / _OUT   JSON lines in (id, say, bundle, title) and out (id, typed, via, notes, ms)
///   ALOUD_BEHAVIOR_CHAIN       "app" (Groq then Haiku, the app's timeouts), "groq" or "haiku" (one model)
///   ALOUD_BEHAVIOR_PAR         cases in flight at once (default 3)
///   ALOUD_BEHAVIOR_FIXUPS=0    turn off the rule-based fix-ups after the model (measures the model alone)
///   ALOUD_BEHAVIOR_MARKERS=1   also loosen the checks on fixed correction cue words (the app doesn't)
///   ALOUD_BEHAVIOR_REPAIR=0    no misheard-word repair pass
///   ALOUD_BEHAVIOR_GROQ_EFFORT  Groq reasoning effort (low / medium)
/// No personal dictionary, so results don't depend on whose Mac runs them.
@Suite("BehaviorReplay", .enabled(if: ProcessInfo.processInfo.environment["ALOUD_BEHAVIOR_IN"] != nil))
struct BehaviorReplay {
    static let env = ProcessInfo.processInfo.environment

    static func cleaner() -> Cleaner {
        let fixups = env["ALOUD_BEHAVIOR_FIXUPS"] != "0"
        let markers = env["ALOUD_BEHAVIOR_MARKERS"] == "1"
        let repair: Cleaner.RepairPolicy = env["ALOUD_BEHAVIOR_REPAIR"] == "0" ? .off : .always
        let effort = env["ALOUD_BEHAVIOR_GROQ_EFFORT"] ?? "low"
        let groq = env["GROQ_API_KEY"].map { OpenAICompatibleLLM.groq(apiKey: $0, effort: effort) as CleanupLLM }
        let haiku = env["ANTHROPIC_API_KEY"].map { AnthropicLLM(apiKey: $0) as CleanupLLM }
        switch env["ALOUD_BEHAVIOR_CHAIN"] ?? "app" {
        case "groq": return Cleaner(chain: [groq].compactMap { $0 }.map { .init($0, timeout: 8) }, repair: repair, repairTimeout: 8, fixups: fixups, correctionMarkers: markers)
        case "haiku": return Cleaner(chain: [haiku].compactMap { $0 }.map { .init($0, timeout: 8) }, repair: repair, repairTimeout: 8, fixups: fixups, correctionMarkers: markers)
        default:
            var chain: [Cleaner.Step] = []
            if let groq { chain.append(.init(groq, timeout: 1.5)) }
            if let haiku { chain.append(.init(haiku, timeout: 2.5)) }
            return Cleaner(chain: chain, repair: repair, repairTimeout: 1.2, fixups: fixups, correctionMarkers: markers)
        }
    }

    struct Item: Sendable { let id, say, bundle, title, app: String }

    @Test func replay() async throws {
        let cleaner = Self.cleaner()
        let items: [Item] = try String(contentsOfFile: Self.env["ALOUD_BEHAVIOR_IN"]!, encoding: .utf8)
            .split(separator: "\n").filter { !$0.isEmpty }.map { line in
                let o = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                return Item(id: o["id"] as? String ?? "", say: o["say"] as? String ?? "", bundle: o["bundle"] as? String ?? "",
                            title: o["title"] as? String ?? "", app: o["app"] as? String ?? "")
            }
        let par = max(1, Int(Self.env["ALOUD_BEHAVIOR_PAR"] ?? "") ?? 3)
        var rows: [String: String] = [:]
        try await withThrowingTaskGroup(of: (String, String).self) { group in
            var next = 0
            func launch() {
                guard next < items.count else { return }
                let item = items[next]
                next += 1
                group.addTask {
                    let ctx = AppContext(bundleID: item.bundle.isEmpty ? nil : item.bundle, appName: item.app,
                                         windowTitle: item.title.isEmpty ? nil : item.title)
                    let clock = ContinuousClock(), t0 = clock.now
                    let r = await cleaner.clean(item.say, context: ctx)
                    let ms = (clock.now - t0).components
                    let row: [String: Any] = [
                        "id": item.id, "typed": r.text, "via": r.via, "mode": r.mode.rawValue,
                        "notes": (r.restructured ? ["restructured"] : []) + r.notes,
                        "ms": Int(ms.seconds * 1000 + ms.attoseconds / 1_000_000_000_000_000),
                    ]
                    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    return (item.id, String(decoding: data, as: UTF8.self))
                }
            }
            for _ in 0..<par { launch() }
            while let (id, row) = try await group.next() {
                rows[id] = row
                launch()
            }
        }
        let out = items.compactMap { rows[$0.id] }.joined(separator: "\n") + "\n"
        try out.write(toFile: Self.env["ALOUD_BEHAVIOR_OUT"]!, atomically: true, encoding: .utf8)
    }
}
