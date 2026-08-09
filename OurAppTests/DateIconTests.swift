import Foundation
import SwiftData
import Testing
@testable import OurApp

struct DateIconTests {
    @Test func thereAreTwelveIconsWithUniqueIDs() {
        let ids = DateIcon.allCases.map(\.rawValue)
        #expect(ids.count == 12)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(""))   // "" means "unmigrated" and must never be an icon
    }

    @Test func everyIDRoundTrips() {
        for icon in DateIcon.allCases {
            #expect(DateIcon.resolve(icon.rawValue) == icon)
        }
    }

    @Test func anUnknownIDFallsBackToHeart() {
        // A row written by a future version, or one that never migrated.
        #expect(DateIcon.resolve("chariot") == .heart)
        #expect(DateIcon.resolve("") == .heart)
    }

    @Test func everyEmojiFromTheRetiredPaletteMaps() {
        let expected: [String: DateIcon] = [
            "🎂": .cake, "🍰": .cake, "✈️": .plane, "🏠": .home,
            "💍": .ring, "🎓": .graduation, "🌸": .flower, "🎁": .gift,
            "⭐️": .star, "💗": .heart, "🌊": .wave, "📍": .pin,
        ]
        for (emoji, icon) in expected {
            #expect(DateIcon.matching(emoji: emoji) == icon, "\(emoji) mapped wrong")
        }
        // The palette had twelve entries; all of them are covered above.
        #expect(expected.count == 12)
    }

    @Test func anUnrecognisedEmojiFallsBackToHeart() {
        #expect(DateIcon.matching(emoji: "🦕") == .heart)
        #expect(DateIcon.matching(emoji: "") == .heart)
    }
}

@MainActor
struct DateIconMigrationTests {
    private func rows(_ context: ModelContext) throws -> [SpecialDate] {
        try context.fetch(FetchDescriptor<SpecialDate>())
    }

    @Test func fillsEmptyIDsFromTheRetiredEmoji() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(SpecialDate(title: "Birthday", emoji: "🎂", date: .now))
        context.insert(SpecialDate(title: "Trip", emoji: "✈️", date: .now))
        context.insert(SpecialDate(title: "Odd", emoji: "🦕", date: .now))
        try context.save()

        DateIconMigration.runIfNeeded(in: container)

        let byTitle = Dictionary(uniqueKeysWithValues: try rows(ModelContext(container))
            .map { ($0.title, $0.icon) })
        #expect(byTitle["Birthday"] == .cake)
        #expect(byTitle["Trip"] == .plane)
        #expect(byTitle["Odd"] == .heart)
    }

    @Test func leavesAChosenIconAlone() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        // Emoji says cake, but the id says star — the id is the user's choice
        // and must win, or migrating twice would overwrite real picks.
        context.insert(SpecialDate(title: "Chosen", emoji: "🎂", date: .now, icon: .star))
        try context.save()

        DateIconMigration.runIfNeeded(in: container)

        #expect(try rows(ModelContext(container)).first?.icon == .star)
    }

    @Test func isIdempotent() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(SpecialDate(title: "Birthday", emoji: "🎂", date: .now))
        try context.save()

        DateIconMigration.runIfNeeded(in: container)
        DateIconMigration.runIfNeeded(in: container)

        let all = try rows(ModelContext(container))
        #expect(all.count == 1)
        #expect(all.first?.icon == .cake)
    }

    @Test func aRepickAfterMigratingSurvivesTheNextRun() throws {
        // The real idempotency risk: migrate, the user changes the icon, the
        // app relaunches. `isIdempotent` can't catch this — there the emoji and
        // the migrated icon agree, so a wrongful re-run is invisible.
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(SpecialDate(title: "Birthday", emoji: "🎂", date: .now))
        try context.save()

        DateIconMigration.runIfNeeded(in: container)
        let migrated = try rows(context)
        #expect(migrated.first?.icon == .cake)

        migrated.first?.icon = .flower          // exercises the setter, too
        try context.save()

        DateIconMigration.runIfNeeded(in: container)

        #expect(try rows(ModelContext(container)).first?.icon == .flower)
    }

    @Test func theIconSetterWritesThroughToTheStoredID() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let date = SpecialDate(title: "Trip", date: .now)
        context.insert(date)
        date.icon = .plane
        try context.save()
        #expect(date.iconID == DateIcon.plane.rawValue)
    }

    @Test func aNewDateKeepsTheIconItWasGiven() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(SpecialDate(title: "Fresh", date: .now, icon: .wave))
        try context.save()
        #expect(try rows(ModelContext(container)).first?.icon == .wave)
    }
}
