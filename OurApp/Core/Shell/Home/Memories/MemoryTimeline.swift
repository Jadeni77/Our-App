import Foundation

/// Ordering the timeline: dated moments newest first, then the ones whose day
/// nobody remembers.
///
/// Pure, and deliberately not a `SortDescriptor`. Two reasons. A `@Query` sort
/// is untestable — the branch review caught the spec claiming newest-first
/// ordering was covered when nothing exercised it. And `day` is anchored to
/// noon UTC (H8), so every memory from one trip ties *exactly*; without the
/// `updatedAt` tiebreak their order is whatever the store happens to return,
/// which can differ between launches.
enum MemoryTimeline {
    struct Split: Equatable {
        var dated: [Memory]
        var undated: [Memory]
    }

    /// Undated memories go last rather than first: `nil` sorting as
    /// `.distantPast` would bury them, and sorting as `.distantFuture` would
    /// put the vaguest moments at the top of the page.
    static func ordered(_ memories: [Memory]) -> Split {
        let dated = memories
            .filter { $0.day != nil }
            .sorted { lhs, rhs in
                guard let left = lhs.day, let right = rhs.day else { return false }
                if left != right { return left > right }
                return lhs.updatedAt > rhs.updatedAt
            }
        let undated = memories
            .filter { $0.day == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        return Split(dated: dated, undated: undated)
    }
}
