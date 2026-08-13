import Foundation
import SwiftData
import Testing
@testable import OurApp

struct CoopLedgerMergeTests {
    private func run(cleared: Bool = true, stars: Int = 0, flings: Int = 0,
                     oneFling: Bool = false) -> CoopLedger.Snapshot {
        CoopLedger.Snapshot(cleared: cleared, bestStars: stars, bestFlings: flings,
                            featOneFling: oneFling)
    }

    @Test func mergingTakesTheBetterRun() {
        let merged = CoopLedger.merged(run(stars: 3, flings: 5), run(stars: 2, flings: 2))
        // LWW would let a two-star attempt clobber a three-star clear purely by
        // being saved later, and the couple's record would go backwards.
        #expect(merged.bestStars == 3)
        #expect(merged.bestFlings == 2)
    }

    @Test func mergingIsOrderIndependent() {
        let a = run(stars: 3, flings: 9, oneFling: true)
        let b = run(stars: 1, flings: 2)
        // Commutative, so both phones reach the same answer without a tiebreak
        // — unlike LWW, which needs `authorID` to converge at all (P21).
        #expect(CoopLedger.merged(a, b) == CoopLedger.merged(b, a))
    }

    @Test func mergingIsIdempotent() {
        let once = CoopLedger.merged(run(stars: 2, flings: 4), run(stars: 3, flings: 6))
        // Sync re-delivers; applying the same thing twice must not drift.
        #expect(CoopLedger.merged(once, once) == once)
    }

    @Test func clearedNeverUnclears() {
        let merged = CoopLedger.merged(run(cleared: true, stars: 2, flings: 3),
                                       run(cleared: false, stars: 0, flings: 0))
        #expect(merged.cleared)
        // A later failed attempt must not undo a level already finished, and
        // must not drag the fling count to a meaningless zero.
        #expect(merged.bestFlings == 3)
    }

    @Test func anUnclearedSideDoesNotWinTheFewestFlings() {
        // 0 means "never cleared", not "cleared in no flings" — the classic
        // way a minimum goes wrong.
        let merged = CoopLedger.merged(run(cleared: false, flings: 0),
                                       run(cleared: true, flings: 7))
        #expect(merged.bestFlings == 7)
    }

    @Test func featsAreOrMergedNeverLost() {
        let merged = CoopLedger.merged(run(oneFling: true), run(oneFling: false))
        #expect(merged.featOneFling)
    }
}

@MainActor
struct CoopLedgerSyncTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func result(_ levelID: UUID, stars: Int, flings: Int) -> CoopLevelResult {
        let row = CoopLevelResult(levelID: levelID)
        row.apply(CoopLedger.Snapshot(cleared: true, bestStars: stars, bestFlings: flings))
        return row
    }

    @Test func bothPhonesFinishingALevelProduceOneRowNotTwo() throws {
        let level = UUID()
        let store = try context()

        // Each phone recorded its own view, independently, while apart.
        let mine = result(level, stars: 2, flings: 6)
        let hers = result(level, stars: 3, flings: 9)
        store.insert(mine)
        try store.save()
        SyncApply.apply(hers.envelope(), in: store, localAuthorID: "me")
        try store.save()

        // The record's identity *is* the level, so two independent creations
        // converge instead of double-counting in the shared star pool.
        let all = try store.fetch(FetchDescriptor<CoopLevelResult>())
        #expect(all.count == 1)
        #expect(all.first?.bestStars == 3)
        #expect(all.first?.bestFlings == 6)
    }

    @Test func aWorseRunArrivingLaterDoesNotDegradeTheRecord() throws {
        let level = UUID()
        let store = try context()
        store.insert(result(level, stars: 3, flings: 2))
        try store.save()

        var stale = result(level, stars: 1, flings: 8).envelope()
        stale.updatedAt = Date().addingTimeInterval(3600)   // strictly newer
        SyncApply.apply(stale, in: store, localAuthorID: "me")
        try store.save()

        // Newer, and still refused — this is the one shared type where "latest"
        // is the wrong question.
        let row = try store.fetch(FetchDescriptor<CoopLevelResult>()).first
        #expect(row?.bestStars == 3)
        #expect(row?.bestFlings == 2)
    }

    @Test func applyingTheSameResultTwiceChangesNothing() throws {
        let store = try context()
        let envelope = result(UUID(), stars: 3, flings: 4).envelope()
        SyncApply.apply(envelope, in: store, localAuthorID: "me")
        let second = SyncApply.apply(envelope, in: store, localAuthorID: "me")
        try store.save()

        #expect(second == false)
        #expect(try store.fetchCount(FetchDescriptor<CoopLevelResult>()) == 1)
    }
}
