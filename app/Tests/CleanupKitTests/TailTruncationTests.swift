import Foundation
import Testing
@testable import CleanupKit

/// BUG-001: cleanup must never return a rewrite that lost the end of the transcript.
@Suite("Cleanup keeps the ending (BUG-001)")
struct CleanupTailTests {
    @Test func groqStopAtTokenCapIsAFailure() throws {
        let body = #"{"choices":[{"finish_reason":"length","message":{"content":"Please take care of"}}]}"#
        #expect(throws: LLMError.truncated) { try OpenAICompatibleLLM.parse(Data(body.utf8)) }
    }

    @Test func claudeStopAtTokenCapIsAFailure() throws {
        let body = #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"Please take care of"}]}"#
        #expect(throws: LLMError.truncated) { try AnthropicLLM.parse(Data(body.utf8)) }
    }

    @Test func tokenCapGrowsWithInput() {
        #expect(outputTokenCap(for: "short", floor: 1200) == 1200)
        #expect(outputTokenCap(for: String(repeating: "word ", count: 2_000), floor: 1200) > 4_000)
    }

    @Test func guardrailRejectsADroppedEnding() {
        // Long enough that losing three words stays under the recall threshold.
        let body = "Refer to the reports in the Aloud project, read the research notes on the island design, "
            + "check the approval card layout, compare the menu bar options, review the event model proposal, "
            + "estimate the effort for the streaming planner, list the risks for the notch placement, "
            + "and then implement the changes"
        let input = body + " for the agent window."
        let output = body + "."
        #expect(Guardrail.check(input: input, output: output, level: .light) == .reject("dropped the ending: changes agent window"))
    }

    @Test func guardrailKeepsATidiedEnding() {
        let input = "um so I leave you to it and you know take care of all of that please"
        let output = "So, I leave you to it. Take care of all of that."
        #expect(Guardrail.check(input: input, output: output, level: .light) == .accept)
    }
}
