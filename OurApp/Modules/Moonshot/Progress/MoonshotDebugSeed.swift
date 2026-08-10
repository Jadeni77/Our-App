#if DEBUG
import Foundation
import SwiftData

/// `-seedPartnerProgress` writes a campaign for *someone else*, so the side-by-side
/// on Moonshot's home screen is reachable headlessly. Two real phones and a
/// played campaign are the only other way to see it.
enum MoonshotDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-seedPartnerProgress") else { return }
        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<MoonshotLevelResult>())) == 0 else { return }

        let mine = MoonshotProgressStore(context: context, partnerID: LocalAuthor.id())
        for stars in [3, 3, 2, 1] {
            mine.recordSolo(levelID: UUID(), cleared: true, stars: stars, flings: 4)
        }
        // A different author id: exactly what arrives over the transport, and
        // what must never be counted as this phone's own.
        let theirs = MoonshotProgressStore(context: context, partnerID: "partner-install")
        for stars in [3, 2, 2] {
            theirs.recordSolo(levelID: UUID(), cleared: true, stars: stars, flings: 5)
        }
        try? context.save()
    }
}
#endif
