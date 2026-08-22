import CloudKit
import Foundation
import SwiftData
import UIKit

/// What a silent push turns into.
///
/// Split out of the app delegate because it is a **rule**, not plumbing: which
/// arriving records deserve to interrupt someone. Rules in this project get to
/// live somewhere they can be read and tested; the delegate keeps only the
/// hook iOS insists on.
@MainActor
enum CoupleTurnAlert {
    /// Turns this phone knows it has already announced. Local, and never
    /// synced: whether *you* were told is nobody else's business, and the same
    /// turn arriving twice must not buzz twice.
    private static let announcedKey = "coop.announcedTurns"

    static func syncAndAnnounce(context: ModelContext? = nil) async -> UIBackgroundFetchResult {
        guard let context = context ?? SharedContext.current else { return .noData }
        let arrived = await SyncStack.tick(context: context)
        let announced = announce(in: context)
        return (announced || !arrived.isEmpty) ? .newData : .noData
    }

    /// - Returns: whether anything was worth saying.
    @discardableResult
    static func announce(in context: ModelContext,
                         defaults: UserDefaults = .standard) -> Bool {
        let me = LocalAuthor.id()
        guard let matches = try? context.fetch(
            FetchDescriptor<CoopMatch>(predicate: CoopMatch.live)) else { return false }

        var already = Set(defaults.stringArray(forKey: announcedKey) ?? [])
        var announcedAnything = false

        for match in matches where match.turnHolder == me && match.turnIndex > 0 {
            // Keyed to the *turn*, not the match: the next turn on the same
            // level is a new thing to be told about, and the same one arriving
            // twice is not.
            let key = "\(match.id.uuidString)#\(match.turnIndex)"
            guard !already.contains(key) else { continue }
            already.insert(key)
            announcedAnything = true
            Task { await CoupleSubscription.announceTurn(level: nil) }
        }

        if announcedAnything {
            defaults.set(Array(already), forKey: announcedKey)
        }
        return announcedAnything
    }
}

/// The one model context a background wake can reach.
///
/// A push arrives with no view hierarchy and therefore no environment, so the
/// container has to be reachable without one. Set once at launch.
@MainActor
enum SharedContext {
    static var current: ModelContext?
}
