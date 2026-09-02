import Foundation

/// Grouping an album's photos the way a physical album reads: newest day
/// first, newest photo first inside each day.
///
/// Pure, and deliberately not a `SortDescriptor` — the same reasoning as
/// `MemoryTimeline`. Grouping by day can't be expressed as a query sort at
/// all, so it has to run in Swift over the fetched photos, and putting it
/// here rather than in the view keeps it testable without a `View` in sight.
enum AlbumSections {
    /// One heading's worth of photos. `day` is `nil` for the one section that
    /// isn't a day at all — the photos nobody dated.
    struct Section: Identifiable, Equatable {
        let day: Date?
        let photos: [Photo]

        /// Derived rather than a fresh `UUID()` per section, so the same day
        /// produces the same id across two calls — `Photo.id(for:)` is the
        /// same pattern for the same reason. The undated section has no
        /// `day` to derive from, so it gets its own fixed anchor instead of
        /// an `id` that has to tolerate `nil`.
        var id: UUID {
            guard let day else { return Self.undatedID }
            return DerivedUUID.from("AlbumSections.day:\(day.timeIntervalSince1970)")
        }

        private static let undatedID = DerivedUUID.from("AlbumSections.undated")
    }

    /// Groups `photos` by the civil day they were taken, newest day first,
    /// newest photo first within a day, with undated photos trailing in a
    /// single section of their own.
    ///
    /// - Every day boundary goes through `SpecialDateSchedule.localDay(of:
    ///   calendar:)`, not a hand-rolled `startOfDay`. A `takenAt` is an
    ///   absolute instant, but the heading above it — "6.11" — is a floating
    ///   civil day (H8), and `localDay` is the one place that already gets
    ///   that conversion right; reimplementing it here has cost this app two
    ///   off-by-one-day bugs.
    /// - `calendar` is threaded into every call that needs one — `localDay`
    ///   here, `sorted` needs none — rather than letting any helper default
    ///   to `.current` on its own. A helper that quietly falls back to
    ///   `.current` while the caller passes something else is exactly what
    ///   shifted every Spark streak by a day once; this function has no
    ///   second calendar to drift out of sync with the first.
    /// - Undated photos are never guessed into "today" or dropped. The
    ///   couple sets dates by hand (`Memory.day`'s own reasoning), so a photo
    ///   with no `takenAt` has to stay visibly its own trailing section
    ///   rather than sliding silently into whichever day it happened to be
    ///   added — `MemoryTimeline.ordered`'s undated split is the same call.
    static func sections(for photos: [Photo], calendar: Calendar = .current) -> [Section] {
        guard !photos.isEmpty else { return [] }

        var byDay: [Date: [Photo]] = [:]
        var undated: [Photo] = []

        for photo in photos {
            guard let takenAt = photo.takenAt else {
                undated.append(photo)
                continue
            }
            let day = SpecialDateSchedule.localDay(of: takenAt, calendar: calendar)
            byDay[day, default: []].append(photo)
        }

        let dated = byDay.keys.sorted(by: >).map { day in
            Section(day: day, photos: byDay[day]!.sorted { $0.sortDate > $1.sortDate })
        }

        guard !undated.isEmpty else { return dated }

        // `sortDate` falls back to `addedAt` for every photo here (they have
        // no `takenAt` by construction), so this section is still
        // newest-first rather than in whatever order the fetch returned.
        let undatedSection = Section(day: nil, photos: undated.sorted { $0.sortDate > $1.sortDate })
        return dated + [undatedSection]
    }
}
