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

/// The backfill that runs once, on the way to schema V2, as `emoji` is dropped.
/// Was a launch-time `DateIconMigration`; the rule is unchanged, its home isn't.
struct RetiredEmojiBackfillTests {
    @Test func anEmptyIDIsFilledFromTheRetiredEmoji() {
        #expect(AppMigrationPlan.backfilledIconID(existing: "", emoji: "🎂")
                == DateIcon.cake.rawValue)
        #expect(AppMigrationPlan.backfilledIconID(existing: "", emoji: "✈️")
                == DateIcon.plane.rawValue)
    }

    @Test func anUnrecognisedEmojiFallsBackToTheHeart() {
        #expect(AppMigrationPlan.backfilledIconID(existing: "", emoji: "🦕")
                == DateIcon.heart.rawValue)
    }

    @Test func aChosenIconIsLeftAlone() {
        // The emoji says cake and the id says star. The id is the owner's
        // actual pick; letting a stale emoji overwrite it would silently
        // change art somebody deliberately chose.
        #expect(AppMigrationPlan.backfilledIconID(existing: DateIcon.star.rawValue,
                                                  emoji: "🎂") == nil)
    }

    @Test func aFilledRowIsNotTouchedASecondTime() {
        let once = AppMigrationPlan.backfilledIconID(existing: "", emoji: "🎂")!
        #expect(AppMigrationPlan.backfilledIconID(existing: once, emoji: "🎂") == nil)
    }
}
