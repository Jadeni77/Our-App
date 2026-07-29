import Testing
@testable import OurApp

struct SmokeTests {
    @Test func harnessRuns() {
        #expect(Bool(true))
    }
}
