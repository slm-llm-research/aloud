import Foundation
import Testing
@testable import InstructFlowCore

struct Boom: Error {}

func after(_ ms: Int, _ result: Result<String, Error>) -> @Sendable () async throws -> String {
    {
        try await Task.sleep(for: .milliseconds(ms))
        return try result.get()
    }
}

@Suite("STT race")
struct STTRaceTests {
    let window = Duration.milliseconds(100)

    @Test func noCloudMeansLocal() async throws {
        let o = try await STTRace.run(cloud: nil, local: after(1, .success("local")), window: window)
        #expect(o == .init(text: "local", source: .local))
    }

    @Test func fastCloudWins() async throws {
        let o = try await STTRace.run(cloud: after(20, .success("cloud")), local: after(5, .success("local")), window: window)
        #expect(o == .init(text: "cloud", source: .cloud))
    }

    @Test func slowCloudLosesToLocal() async throws {
        let clock = ContinuousClock()
        let t0 = clock.now
        let o = try await STTRace.run(cloud: after(2_000, .success("cloud")), local: after(10, .success("local")),
                                      window: window)
        #expect(o == .init(text: "local", source: .local))
        #expect(clock.now - t0 < .milliseconds(1_000))  // didn't wait for the slow cloud
    }

    @Test func cloudErrorFallsBackToLocal() async throws {
        let o = try await STTRace.run(cloud: after(5, .failure(Boom())), local: after(30, .success("local")), window: window)
        #expect(o.source == .local)
    }

    @Test func emptyCloudFallsBackToLocal() async throws {
        let o = try await STTRace.run(cloud: after(5, .success("  ")), local: after(30, .success("local")), window: window)
        #expect(o == .init(text: "local", source: .local))
    }

    @Test func localFailureWaitsForLateCloud() async throws {
        let o = try await STTRace.run(cloud: after(300, .success("cloud")), local: after(5, .failure(Boom())), window: window)
        #expect(o == .init(text: "cloud", source: .cloud))
    }

    @Test func bothFailing() async {
        await #expect(throws: STTRace.RaceError.bothFailed) {
            try await STTRace.run(cloud: after(5, .failure(Boom())), local: after(5, .failure(Boom())), window: window)
        }
    }
}
