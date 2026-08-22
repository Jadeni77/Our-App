import Foundation
import SwiftData
import Testing
@testable import OurApp

/// Which arriving records deserve to interrupt someone.
@MainActor
struct CoupleTurnAlertTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func defaults(_ name: String = UUID().uuidString) throws -> UserDefaults {
        try #require(UserDefaults(suiteName: name))
    }

    private func match(holder: String, index: Int) -> CoopMatch {
        let match = CoopMatch(levelID: UUID(), participants: [holder, "them"],
                              turnHolder: holder)
        match.turnIndex = index
        return match
    }

    /// The point of the whole slice: a turn handed to you says so.
    @Test func aTurnHandedToYouIsAnnounced() throws {
        let store = try context()
        store.insert(match(holder: LocalAuthor.id(), index: 1))
        try store.save()
        #expect(CoupleTurnAlert.announce(in: store, defaults: try defaults()))
    }

    /// **Silence is most of the design.** A couple's app that buzzes for
    /// everything becomes a couple's app you mute.
    @Test func aTurnThatIsNotYoursSaysNothing() throws {
        let store = try context()
        store.insert(match(holder: "them", index: 1))
        try store.save()
        #expect(CoupleTurnAlert.announce(in: store, defaults: try defaults()) == false)
    }

    /// A match nobody has played yet is not a turn waiting for you — it is a
    /// level you happened to open first.
    @Test func anUnplayedMatchSaysNothing() throws {
        let store = try context()
        store.insert(match(holder: LocalAuthor.id(), index: 0))
        try store.save()
        #expect(CoupleTurnAlert.announce(in: store, defaults: try defaults()) == false)
    }

    /// Sync redelivers routinely, and the same turn must not buzz twice.
    @Test func theSameTurnIsAnnouncedOnlyOnce() throws {
        let store = try context()
        store.insert(match(holder: LocalAuthor.id(), index: 1))
        try store.save()
        let remembered = try defaults()

        #expect(CoupleTurnAlert.announce(in: store, defaults: remembered))
        #expect(CoupleTurnAlert.announce(in: store, defaults: remembered) == false)
    }

    /// But the *next* turn on the same level is a new thing to be told about —
    /// which is why what is remembered is keyed to the turn, not the match.
    @Test func theNextTurnOnTheSameLevelIsAnnouncedAgain() throws {
        let store = try context()
        let live = match(holder: LocalAuthor.id(), index: 1)
        store.insert(live)
        try store.save()
        let remembered = try defaults()
        #expect(CoupleTurnAlert.announce(in: store, defaults: remembered))

        live.turnIndex = 3
        try store.save()
        #expect(CoupleTurnAlert.announce(in: store, defaults: remembered))
    }

    /// A finished level is not waiting for anybody.
    @Test func aClearedLevelSaysNothing() throws {
        let store = try context()
        let done = match(holder: LocalAuthor.id(), index: 2)
        done.finishedAt = .now
        store.insert(done)
        try store.save()
        #expect(CoupleTurnAlert.announce(in: store, defaults: try defaults()) == false)
    }
}
