import CloudKit
import Foundation
import UIKit
import OSLog
import UserNotifications

/// Being told the moment something changes, rather than finding out later.
///
/// A **silent** push: CloudKit wakes the app, the app syncs, and only then does
/// it decide whether there is anything worth saying. That ordering is the whole
/// design.
///
/// - Only the receiving phone knows whether an arriving turn is *yours*, so
///   only it can word the notification. The sender cannot, and should not have
///   to.
/// - No message text ever leaves the device. What crosses the network is a
///   record; the sentence is composed here.
/// - A change that does not concern you makes no sound at all. A couple's app
///   that pushes for everything becomes a couple's app you mute.
@MainActor
enum CoupleSubscription {
    private static let subscriptionID = "couple-zone-changes"
    private static var log: Logger { Logger(subsystem: "OurApp", category: "push") }

    /// Registers for silent pushes on whichever database this phone syncs
    /// against. Idempotent — CloudKit treats a repeat save as a no-op — so it
    /// is simply run at launch rather than remembered somewhere that could
    /// itself go stale.
    static func ensure(on database: CKDatabase) async {
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let notification = CKSubscription.NotificationInfo()
        // **Silent.** No alert, no badge, no sound from CloudKit itself: it
        // wakes us, and we decide what — if anything — to say.
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification

        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            log.info("subscribed to \(database.databaseScope.rawValue) zone changes")
        } catch {
            // Not fatal, and not worth a screen: without a subscription the app
            // still syncs whenever it is opened. You lose immediacy, not data.
            log.error("could not subscribe: \(error.localizedDescription)")
        }
    }

    /// Asks once, and only for what is used.
    ///
    /// Requested at the point the couple actually shares, not at first launch:
    /// a permission prompt before the app has done anything for you is a prompt
    /// you decline.
    @discardableResult
    static func requestPermission() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// Says the one thing worth saying.
    static func announceTurn(level: String?) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your turn")
        content.body = level.map {
            String(localized: "\($0) is waiting for your shot.")
        } ?? String(localized: "A level is waiting for your shot.")
        content.sound = .default

        // No trigger: it fires now. The delay already happened on the network.
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
