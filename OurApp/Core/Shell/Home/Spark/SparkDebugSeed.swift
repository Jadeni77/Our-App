#if DEBUG
import Foundation
import SwiftData

/// Headless screenshot verification can't tap, so these write a history:
/// `-seedSpark` a live 12-day streak checked in today, `-seedSparkAtRisk` a run
/// that includes yesterday but not today — the state the whole streak rule
/// turns on, and one that is otherwise only reachable by waiting for midnight.
///
/// DEBUG only, and both decline when any check-in already exists.
enum SparkDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer, authorID: String) {
        let arguments = ProcessInfo.processInfo.arguments
        let lit = arguments.contains("-seedSpark")
        let atRisk = arguments.contains("-seedSparkAtRisk")
        guard lit || atRisk else { return }

        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<CheckIn>())) == 0 else { return }

        let calendar = Calendar.current
        // At risk starts at yesterday, so today is deliberately missing.
        let offsets = lit ? Array(0...11) : Array(1...5)
        for offset in offsets {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            CheckInStore.checkIn(in: context, authorID: authorID, on: day)
        }
    }
}
#endif
