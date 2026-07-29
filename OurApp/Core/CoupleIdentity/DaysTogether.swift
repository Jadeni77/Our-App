import Foundation

/// Day math for the "together for N days" counter.
enum DaysTogether {
    /// The anniversary itself counts as day 1 (how couples actually count).
    /// Compares calendar days, not 24h intervals, so the number rolls at midnight.
    static func days(from anniversary: Date, to now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: anniversary)
        let end = calendar.startOfDay(for: now)
        let diff = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(diff + 1, 1)
    }
}
