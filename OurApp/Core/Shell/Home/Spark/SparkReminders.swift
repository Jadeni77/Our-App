import Foundation
import UserNotifications

/// The thin, untestable shell around `UNUserNotificationCenter`. Every decision
/// worth testing lives in `SparkReminderPlan`; this only carries them out.
///
/// Local notifications only — no APNs, no entitlement, no `$99` (P19). Nothing
/// here talks to a network.
@MainActor
enum SparkReminders {
    enum Defaults {
        static let enabled = "spark.reminderEnabled"
        static let hour = "spark.reminderHour"
        static let minute = "spark.reminderMinute"
        /// 21:00 — late enough to mean "before the day ends", early enough not
        /// to arrive after someone is asleep.
        static let defaultHour = 21
    }

    static func time(from defaults: UserDefaults = .standard) -> DateComponents {
        DateComponents(hour: defaults.object(forKey: Defaults.hour) as? Int ?? Defaults.defaultHour,
                       minute: defaults.object(forKey: Defaults.minute) as? Int ?? 0)
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asked for **only when the toggle is turned on**, never at launch. A
    /// permission prompt on first run, before anyone knows what the app is, is
    /// the fastest way to earn a permanent "Don't Allow" that then has to be
    /// undone in iOS Settings.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces every pending spark reminder with what the plan says should be
    /// pending. Called after a check-in, on foreground, and when the app
    /// language changes — content is resolved at schedule time, so a language
    /// switch would otherwise leave a fortnight of notifications in the old one.
    /// `at` defaults to the stored time, resolved inside rather than in the
    /// signature — a default argument is evaluated in a nonisolated context and
    /// can't reach a main-actor member.
    static func reschedule(checkedIn: [Date],
                           enabled: Bool,
                           at time: DateComponents? = nil,
                           now: Date = .now,
                           calendar: Calendar = .current) async {
        let time = time ?? Self.time()
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(SparkReminderPlan.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        guard enabled, await authorizationStatus() == .authorized else { return }

        for fire in SparkReminderPlan.pending(from: now, at: time,
                                              checkedIn: checkedIn, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Your spark")
            // No streak number in the body. A request scheduled nine days out
            // cannot know what the streak will be by then, and a notification
            // that states a wrong number is worse than one that states none.
            content.body = String(localized: "Check in before midnight to keep it going")
            content.sound = .default

            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(
                identifier: SparkReminderPlan.identifier(for: fire, calendar: calendar),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}
