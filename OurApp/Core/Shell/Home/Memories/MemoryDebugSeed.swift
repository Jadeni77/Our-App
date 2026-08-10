#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Headless screenshot verification can't tap a `PhotosPicker`, so
/// `-seedMemories` writes a few moments with generated pictures. One of them is
/// deliberately undated: the "Sometime" heading is otherwise unreachable
/// without a device pass, and an unphotographable state is an unverifiable one.
///
/// DEBUG only, and it declines when the timeline already holds anything, so it
/// can never sit on top of real memories.
enum MemoryDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer,
                               identity: CoupleIdentityStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedMemories") else { return }

        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<Memory>())) == 0 else { return }
        let store = MemoryPhotoStore()
        let calendar = Calendar.current
        // The third has no day — that is the whole point of the seed.
        let seeds: [(note: String, daysAgo: Int?, colours: [UIColor])] = [
            ("Kyoto, first morning", 3, [.systemPink, .systemOrange]),
            ("The long way home", 20, [.systemTeal]),
            ("no idea when this was", nil, [.systemIndigo, .systemPurple, .systemBlue]),
        ]
        for seed in seeds {
            let ids = seed.colours.compactMap { try? store.save(picture($0)) }
            guard !ids.isEmpty else { continue }
            let day = seed.daysAgo.flatMap {
                calendar.date(byAdding: .day, value: -$0, to: .now)
            }
            context.insert(Memory(note: seed.note, day: day,
                                  authorID: identity.authorID, photoIDs: ids))
        }
        try? context.save()
    }

    private static func picture(_ colour: UIColor) -> Data {
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.22).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 120, y: 120, width: 360, height: 360))
        }.jpegData(compressionQuality: 0.9)!
    }
}
#endif
