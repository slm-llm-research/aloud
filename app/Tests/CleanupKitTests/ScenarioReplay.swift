import Foundation
import Testing
@testable import CleanupKit

/// Runs the app's cleanup (same chain, timeouts and dictionary as the app) over transcripts prepared by
/// `bench/scenario_eval.py replay`, and writes what would have been typed. Not a pass/fail test: the
/// harness scores the output. Input/output: JSON lines given by ALOUD_REPLAY_IN / _OUT.
@Suite("ScenarioReplay", .enabled(if: ProcessInfo.processInfo.environment["ALOUD_REPLAY_IN"] != nil))
struct ScenarioReplay {
    static let env = ProcessInfo.processInfo.environment

    @Test func replay() async throws {
        var chain: [Cleaner.Step] = []
        if let k = Self.env["GROQ_API_KEY"] { chain.append(.init(OpenAICompatibleLLM.groq(apiKey: k), timeout: 1.5)) }
        if let k = Self.env["ANTHROPIC_API_KEY"] { chain.append(.init(AnthropicLLM(apiKey: k), timeout: 2.5)) }
        let dictURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Aloud/dictionary.txt")
        let dict = PersonalDictionary.parse((try? String(contentsOf: dictURL, encoding: .utf8)) ?? "")
        let cleaner = Cleaner(chain: chain, dictionary: dict)

        let input = try String(contentsOfFile: Self.env["ALOUD_REPLAY_IN"]!, encoding: .utf8)
        var out = ""
        let clock = ContinuousClock()
        for line in input.split(separator: "\n") where !line.isEmpty {
            let item = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            let heard = item["heard"] as? String ?? ""
            let ctx = AppContext(bundleID: item["bundle"] as? String, windowTitle: item["title"] as? String)
            let t0 = clock.now
            let r = await cleaner.clean(heard, context: ctx)
            let ms = (clock.now - t0).components
            let tags = (r.restructured ? ["restructured"] : []) + r.notes
            let row: [String: Any] = [
                "id": item["id"] as? String ?? "", "heard": heard, "typed": r.text,
                "cleanup": "\(r.via) [\(tags.joined(separator: "; "))]", "app": ctx.bundleID ?? "",
                "cleanup_ms": Int(ms.seconds * 1000 + ms.attoseconds / 1_000_000_000_000_000),
            ]
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            out += String(decoding: data, as: UTF8.self) + "\n"
        }
        try out.write(toFile: Self.env["ALOUD_REPLAY_OUT"]!, atomically: true, encoding: .utf8)
    }
}
