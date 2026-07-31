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
        // it on page 0, but its hosting view owns the live gesture — the
        // slot clamps to page 1's window and page 0 stays untouched.
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c", "d", "e", "f"), dragged: .app("f"),
            insertAt: 0, capacity: 4, originPage: 1)
        #expect(moduleIDs(pages) == [["a", "b", "c", "d"], ["f", "e"]])
    }

    @Test func previewClampsTheSlotIntoTheOriginPageWindow() {
        // "a" starts on page 0 and previews to the very end (page 1's only
        // slot) — the clamp keeps it in page 0's last slot instead.
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c", "d", "e"), dragged: .app("a"),
            insertAt: 4, capacity: 4, originPage: 0)
        #expect(moduleIDs(pages) == [["b", "c", "d", "a"], ["e"]])
    }

    @Test func previewKeepsThePageCountAndTheOtherPagesStable() {
        // The state that used to collapse a page mid-drag: the last page
        // holds only the dragged tile. Every page but the origin must be
        // byte-identical to the resting layout, and the count must hold —
        // the pager's dots, edge-flip bounds, and position all read it.
        let items = apps("a", "b", "c", "d", "e")
        let resting = SpringboardPager.pages(of: items, capacity: 4)
        let preview = SpringboardPager.previewPages(
            items: items, dragged: .app("e"),
            insertAt: 0, capacity: 4, originPage: 1)
        #expect(preview.count == resting.count)
        #expect(moduleIDs(preview) == [["a", "b", "c", "d"], ["e"]])
    }

    @Test func previewClampsAnOutOfRangeOriginPage() {
        // A stale origin (cancelled drag, layout shrank) must still honor
        // the invariant rather than silently skipping the clamp.
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c"), dragged: .app("c"),
            insertAt: 0, capacity: 2, originPage: 9)
        #expect(moduleIDs(pages) == [["a", "b"], ["c"]])
    }

    @Test func previewWithUnknownDraggedIDFallsBackToPlainPages() {
        let pages = SpringboardPager.previewPages(
            items: apps("a", "b", "c"), dragged: .app("zz"),
            insertAt: 1, capacity: 2, originPage: 0)
        #expect(moduleIDs(pages) == [["a", "b"], ["c"]])
    }
}
