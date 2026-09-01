import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct AlbumSectionsTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// A fixed UTC gregorian calendar for building unambiguous `takenAt`
    /// instants — the same reasoning as `SpecialDateScheduleTests`.
    private func utc() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func instant(_ year: Int, _ month: Int, _ day: Int,
                         _ hour: Int = 12, _ minute: Int = 0) -> Date {
        utc().date(from: DateComponents(year: year, month: month, day: day,
                                        hour: hour, minute: minute))!
    }

    @discardableResult
    private func photo(_ store: ModelContext, asset: String, takenAt: Date?) -> Photo {
        let photo = Photo(assetID: asset, authorID: "me", takenAt: takenAt)
        store.insert(photo)
        return photo
    }

    // MARK: Grouping by day

    @Test func threeDaysProduceThreeSectionsNewestDayFirst() throws {
        let store = try context()
        let first = photo(store, asset: "first", takenAt: instant(2026, 8, 1))
        let second = photo(store, asset: "second", takenAt: instant(2026, 8, 5))
        let third = photo(store, asset: "third", takenAt: instant(2026, 8, 9))
        try store.save()

        // Shuffled input on purpose — the order the sections come out in must
        // come from the grouping, not from the order photos were handed in.
        let sections = AlbumSections.sections(for: [second, first, third], calendar: utc())

        #expect(sections.count == 3)
        #expect(sections.map { $0.photos.map(\.assetID) } == [["third"], ["second"], ["first"]])
    }

    @Test func sameDayPhotosLandInOneSectionNewestFirstInside() throws {
        let store = try context()
        let morning = photo(store, asset: "morning", takenAt: instant(2026, 8, 1, 8))
        let noon = photo(store, asset: "noon", takenAt: instant(2026, 8, 1, 12))
        let evening = photo(store, asset: "evening", takenAt: instant(2026, 8, 1, 20))
        try store.save()

        let sections = AlbumSections.sections(for: [morning, evening, noon], calendar: utc())

        #expect(sections.count == 1)
        #expect(sections[0].photos.map(\.assetID) == ["evening", "noon", "morning"])
    }

    // MARK: The undated section

    @Test func undatedPhotosFormOneTrailingSectionAfterEveryDatedOne() throws {
        let store = try context()
        let dated1 = photo(store, asset: "dated1", takenAt: instant(2026, 8, 1))
        let dated2 = photo(store, asset: "dated2", takenAt: instant(2026, 8, 5))
        let undated1 = photo(store, asset: "undated1", takenAt: nil)
        let undated2 = photo(store, asset: "undated2", takenAt: nil)
        let undated3 = photo(store, asset: "undated3", takenAt: nil)
        try store.save()

        // Interleaved on purpose: an undated photo sitting between two dated
        // ones in the input must still end up in the single trailing section,
        // not filed next to whichever dated photo it happened to sit beside.
        let sections = AlbumSections.sections(
            for: [undated1, dated1, undated2, dated2, undated3], calendar: utc())

        #expect(sections.count == 3)
        #expect(sections.dropLast().allSatisfy { $0.day != nil })
        #expect(sections.last?.day == nil)
        #expect(Set(sections.last?.photos.map(\.assetID) ?? []) ==
                Set(["undated1", "undated2", "undated3"]))
    }

    @Test func allUndatedInputGivesExactlyOneSection() throws {
        let store = try context()
        let a = photo(store, asset: "a", takenAt: nil)
        let b = photo(store, asset: "b", takenAt: nil)
        let c = photo(store, asset: "c", takenAt: nil)
        try store.save()

        let sections = AlbumSections.sections(for: [a, b, c], calendar: utc())

        #expect(sections.count == 1)
        #expect(sections[0].day == nil)
        #expect(Set(sections[0].photos.map(\.assetID)) == Set(["a", "b", "c"]))
    }

    @Test func emptyInputGivesNoSections() {
        #expect(AlbumSections.sections(for: [], calendar: utc()).isEmpty)
    }

    // MARK: Timezone sweep

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// The one property the whole grouping rests on: which day a photo lands
    /// in, and the shape of the sections that come out of it, must not depend
    /// on the *reader's* own timezone. `SpecialDateSchedule.localDay` anchors
    /// the civil day through a fixed UTC extraction precisely so that two
    /// phones — one in Kiritimati (UTC+14), one in Midway (UTC−11), a 25-hour
    /// spread with no instant common to both — agree on which heading a
    /// photo sits under.
    ///
    /// A hand-rolled `calendar.startOfDay(for: takenAt)` instead of
    /// `localDay` would read the near-midnight photo below as the 15th in
    /// Kiritimati and the 14th in Midway, splitting or merging sections
    /// depending on the zone — this is the boundary error the sweep exists to
    /// catch, not a check that happens to pass everywhere trivially.
    @Test func groupingShapeAgreesAcrossTimezones() throws {
        let store = try context()
        // 23:45 UTC on the 14th: the instant a reader-timezone-dependent
        // boundary gets wrong in one direction or the other for at least one
        // of the zones below.
        let midnightEdge = photo(store, asset: "edge", takenAt: instant(2026, 8, 14, 23, 45))
        let sameDayEarlier = photo(store, asset: "earlier", takenAt: instant(2026, 8, 14, 2))
        let priorDay = photo(store, asset: "prior", takenAt: instant(2026, 8, 10, 12))
        let undated = photo(store, asset: "undated", takenAt: nil)
        try store.save()

        let zones = ["America/New_York", "Asia/Shanghai", "Europe/London",
                     "Pacific/Kiritimati", "Pacific/Midway", "UTC"]

        for zone in zones {
            let reader = calendar(zone)
            let sections = AlbumSections.sections(
                for: [midnightEdge, sameDayEarlier, priorDay, undated], calendar: reader)

            #expect(sections.count == 3, "\(zone) produced \(sections.count) sections")
            #expect(sections[0].photos.map(\.assetID) == ["edge", "earlier"],
                    "\(zone) grouped the 14th wrong")
            #expect(sections[1].photos.map(\.assetID) == ["prior"],
                    "\(zone) grouped the 10th wrong")
            #expect(sections[2].day == nil && sections[2].photos.map(\.assetID) == ["undated"],
                    "\(zone) misplaced the undated section")

            // Not just the shape: the heading date itself has to come from
            // *this* reader's calendar, not from a default `.current` the
            // grouping call forgot to override.
            let expectedHeading = reader.date(from: DateComponents(year: 2026, month: 8, day: 14))!
            #expect(sections[0].day == expectedHeading,
                    "\(zone) built the day heading in the wrong calendar")
        }
    }
}
