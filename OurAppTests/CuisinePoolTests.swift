import Testing
@testable import OurApp

struct CuisinePoolTests {
    @Test func poolHasThirtyToFortyUniqueEntries() {
        #expect(CuisinePool.all.count >= 30)
        #expect(CuisinePool.all.count <= 40)
        #expect(Set(CuisinePool.all.map(\.name)).count == CuisinePool.all.count)
    }

    @Test func drawReturnsAPoolMember() {
        #expect(CuisinePool.all.contains(CuisinePool.draw()))
    }

    @Test func drawNeverReturnsTheExcludedCuisine() {
        let excluded = CuisinePool.all[0]
        for _ in 0..<200 {
            #expect(CuisinePool.draw(excluding: excluded) != excluded)
        }
    }
}
