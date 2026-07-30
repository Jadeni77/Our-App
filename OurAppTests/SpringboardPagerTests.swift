import Foundation
import Testing
@testable import OurApp

struct SpringboardPagerTests {
    private func apps(_ ids: String...) -> [GamesLayout.Item] {
        ids.map { .app(moduleID: $0) }
    }

    private func moduleIDs(_ pages: [[GamesLayout.Item]]) -> [[String]] {
        pages.map { page in
            page.map { item in
                guard case .app(let moduleID) = item else { return "?" }
                return moduleID
            }
        }
    }

    // MARK: - Capacity

    @Test func capacityCountsWholeRowsThatFit() {
        // 3.5 row-pitches of height → 3 full rows.
        let capacity = SpringboardPager.capacity(columns: 4, availableHeight: 400,
                                                 tileHeight: 100, rowSpacing: 20)
        #expect(capacity == 12)
    }

    @Test func capacityNeverDropsBelowOneRow() {
        let capacity = SpringboardPager.capacity(columns: 4, availableHeight: 50,
                                                 tileHeight: 100, rowSpacing: 20)
        #expect(capacity == 4)
    }

    @Test func capacityFailsSoftOnDegenerateMeasurements() {
        #expect(SpringboardPager.capacity(columns: 4, availableHeight: 400,
                                          tileHeight: 0, rowSpacing: 20) == 4)
        #expect(SpringboardPager.capacity(columns: 0, availableHeight: 400,
                                          tileHeight: 100, rowSpacing: 20) == 0)
    }

    // MARK: - Page flow

    @Test func pagesChunkInOrderWithRemainderLast() {
        let pages = SpringboardPager.pages(of: apps("a", "b", "c", "d", "e"), capacity: 4)
        #expect(moduleIDs(pages) == [["a", "b", "c", "d"], ["e"]])
    }

    @Test func exactMultipleFillsPagesEvenly() {
        let pages = SpringboardPager.pages(of: apps("a", "b", "c", "d"), capacity: 2)
        #expect(moduleIDs(pages) == [["a", "b"], ["c", "d"]])
    }

    @Test func noItemsMeansNoPages() {
        #expect(SpringboardPager.pages(of: [GamesLayout.Item](), capacity: 4).isEmpty)
    }

    @Test func degenerateCapacityKeepsEverythingOnOnePage() {
        let pages = SpringboardPager.pages(of: apps("a", "b"), capacity: 0)
        #expect(moduleIDs(pages) == [["a", "b"]])
    }

    // MARK: - Drag preview (the origin-page clamp)

    @Test func previewOnTheSamePageShowsTheGapAtTheInsertionSlot() {
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c", "d", "e"), dragged: .app("b"),
            insertAt: 2, capacity: 4, originPage: 0)
        #expect(moduleIDs(pages) == [["a", "c", "b", "d"], ["e"]])
    }

    @Test func previewNeverMovesTheDraggedTileOffItsOriginPage() {
        // Dragging "f" (page 1) toward the front: the flat preview would put
        // it on page 0, but its hosting view owns the live gesture — it must
        // stay on page 1.
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c", "d", "e", "f"), dragged: .app("f"),
            insertAt: 0, capacity: 4, originPage: 1)
        #expect(moduleIDs(pages) == [["a", "b", "c"], ["d", "e", "f"]])
    }

    @Test func previewClampBackToOriginSurvivesEmptyingAPage() {
        // "a" starts on page 0 and previews to the very end, which would
        // leave it alone on page 1 — the clamp folds it back onto page 0
        // (one invisible overflow cell) and drops the empty page.
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c", "d", "e"), dragged: .app("a"),
            insertAt: 4, capacity: 4, originPage: 0)
        #expect(moduleIDs(pages) == [["b", "c", "d", "e", "a"]])
    }

    @Test func previewWithUnknownDraggedIDFallsBackToPlainPages() {
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c"), dragged: .app("zz"),
            insertAt: 1, capacity: 2, originPage: 0)
        #expect(moduleIDs(pages) == [["a", "b"], ["c"]])
    }
}
