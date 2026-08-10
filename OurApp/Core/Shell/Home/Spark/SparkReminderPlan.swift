import Foundation

/// Which days should have a reminder pending, as a pure function.
///
/// **One non-repeating request per day, not one repeating trigger.** A repeating
/// daily trigger can't skip an occurrence, so checking in at 9am would still
/// produce a 9pm "don't lose your spark" — a notification actively contradicted
/// by what you already did. Individual requests can simply be removed.
///
/// A 14-day horizon sits far inside iOS's 64-pending limit and survives a
/// fortnight of never opening the app.
enum SparkReminderPlan {
    static let horizon = 14
    static let identifierPrefix = "spark-reminder-"

    /// `spark-reminder-2026-08-09`. Built from components rather than a
    /// `DateFormatter` so it can never pick up a locale — a Buddhist or Persian
    /// calendar would otherwise silently change the ids, and the removal that
    /// silences a day looks them up by exact string.
    static func identifier(for fireDate: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: fireDate)
        return identifierPrefix + String(format: "%04d-%02d-%02d",
                                         parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The fire dates that should be pending right now.
    ///
    /// - `checkedIn` takes **stored anchors** (noon UTC, H8), normalised here
    ///   the same way `SparkStreak` normalises them, so the two can never
    ///   disagree about which day is which.
    static func pending(from now: Date,
                        at time: DateComponents,
                        checkedIn: [Date],
                        horizon: Int = horizon,
                        calendar: Calendar = .current) -> [Date] {
        let done = Set(checkedIn.map { SpecialDateSchedule.localDay(of: $0, calendar: calendar) })
        let today = calendar.startOfDay(for: now)

        return (0..<horizon).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  !done.contains(day),
                  let fire = calendar.date(bySettingHour: time.hour ?? 21,
                                           minute: time.minute ?? 0,
                                           second: 0,
                                           of: day),
                  // A fire date already past is not a reminder, it is a
                  // notification that arrives instantly on the next launch.
                  fire > now
            else { return nil }
            return fire
        }
    }
}
