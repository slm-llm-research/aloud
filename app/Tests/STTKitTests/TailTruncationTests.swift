import Foundation
import Testing
@testable import STTKit

/// BUG-001: the last words of long dictations went missing.
@Suite("Tail truncation (BUG-001)")
struct TailTruncationTests {
    /// Scribe committed a segment on its own while the key was held; `finish()` used to return that
    /// segment at once and drop the one our final commit produced.
    @Test func waitsForTheSegmentAfterTheFinalCommit() async throws {
        let t = ScribeTranscript()
        t.committed("So what I'm thinking about is")
        try t.markFinished()
        let result = Task {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in t.wait(c) }
        }
        try await Task.sleep(for: .milliseconds(50))
        t.committed("adding a trailing pad to the recorder.")
        #expect(try await result.value == "So what I'm thinking about is adding a trailing pad to the recorder.")
        #expect(t.diagnostics == "segments=2 early=1 final=yes")
    }

    @Test func finalSegmentBeforeWaitIsStillReturned() async throws {
        let t = ScribeTranscript()
        try t.markFinished()
        t.committed("hello world")
        let text = try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in t.wait(c) }
        #expect(text == "hello world")
    }

    @Test func timeoutSettlesForEarlierSegments() async throws {
        let t = ScribeTranscript()
        t.committed("first part")
        try t.markFinished()
        let result = Task {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in t.wait(c) }
        }
        try await Task.sleep(for: .milliseconds(20))
        t.timeout()
        #expect(try await result.value == "first part")
        #expect(t.diagnostics.hasSuffix("final=timeout"))
    }

    @Test func emptyFinalSegmentIsNotJoined() async throws {
        let t = ScribeTranscript()
        t.committed("all of it")
        try t.markFinished()
        t.committed("")
        let text = try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in t.wait(c) }
        #expect(text == "all of it")
    }
}
