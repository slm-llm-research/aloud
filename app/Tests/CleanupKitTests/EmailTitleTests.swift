import Testing
@testable import CleanupKit
@Test func titledGreeting() {
    #expect(OutputHygiene.finish("Dear Ms. Varga, I'm writing to confirm our booking. Kind regards, Petra", mode: .email)
            == "Dear Ms. Varga,\n\nI'm writing to confirm our booking.\n\nKind regards,\nPetra")
}
