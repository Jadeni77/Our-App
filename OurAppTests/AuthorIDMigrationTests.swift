import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct AuthorIDMigrationTests {
    private func makeContainer() throws -> ModelContainer {
        try Persistence.makeContainer(inMemory: true)
    }

    @Test func legacyPartnerIDsBecomeThisInstallsID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        DailyQuestionStore.write("mine", in: context, questionID: "q01",
                                 day: .now, authorID: Partner.one.rawValue)
        context.insert(Memory(note: "ours", day: .now,
                              authorID: Partner.two.rawValue, photoIDs: ["a"]))
        try context.save()

        AuthorIDMigration.runIfNeeded(in: container, authorID: "this-install")

        // Both halves land on this install: nothing has ever synced, so every
        // row on this phone was written on this phone, whichever half the owner
        // had told the app it was at the time.
        let read = ModelContext(container)
        #expect(try read.fetch(FetchDescriptor<QuestionAnswer>())
            .allSatisfy { $0.authorID == "this-install" })
        #expect(try read.fetch(FetchDescriptor<Memory>())
            .allSatisfy { $0.authorID == "this-install" })
    }

    @Test func aSpecialDateWithNoAuthorGetsOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = SpecialDate(title: "First trip", date: .now)
        date.authorID = nil
        context.insert(date)
        try context.save()

        AuthorIDMigration.runIfNeeded(in: container, authorID: "this-install")

        let stored = try ModelContext(container).fetch(FetchDescriptor<SpecialDate>()).first
        #expect(stored?.authorID == "this-install")
    }

    @Test func runningItAgainLeavesMigratedRowsAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        DailyQuestionStore.write("mine", in: context, questionID: "q01",
                                 day: .now, authorID: Partner.one.rawValue)
        try context.save()

        AuthorIDMigration.runIfNeeded(in: container, authorID: "first-run")
        // A second run with a *different* id stands in for the real hazard: a
        // migration that doesn't recognise its own output rewrites every row
        // again on every launch. Idempotence here comes from matching the old
        // values, not from a defaults latch that can go stale (H14).
        AuthorIDMigration.runIfNeeded(in: container, authorID: "second-run")

        let stored = try ModelContext(container).fetch(FetchDescriptor<QuestionAnswer>()).first
        #expect(stored?.authorID == "first-run")
    }

    @Test func anAlreadyModernRowIsNotTouched() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID().uuidString
        context.insert(Memory(note: "already fine", day: .now,
                              authorID: id, photoIDs: ["a"]))
        try context.save()

        AuthorIDMigration.runIfNeeded(in: container, authorID: "someone-else")

        let stored = try ModelContext(container).fetch(FetchDescriptor<Memory>()).first
        #expect(stored?.authorID == id)
    }
}
