import SwiftData
import SwiftUI

/// Home's check-in: tap to 打卡 for today, and carry the streak.
///
/// Sits under the day counter because that is where the owner asked for it —
/// *"it must be somewhere easy to see and convenient"* — and inside the hero's
/// `geometryGroup`'d subtree, so nothing here may carry a `repeatForever`
/// animation (H25).
struct SparkPill: View {
    @Environment(CoupleIdentityStore.self) private var identity
    @Environment(\.modelContext) private var context
    @Query(filter: CheckIn.visible) private var checkIns: [CheckIn]

    @State private var showingSheet = SparkPill.opensSheetAtLaunch

    /// `-sparkSheet` opens the sheet at launch so headless screenshots reach
    /// copy that otherwise needs a tap. Read as initial state, not in
    /// `onAppear` — a lifecycle modifier on a view that might not be mounted is
    /// how the Daily Question badge silently stopped installing (H18).
    private static var opensSheetAtLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-sparkSheet")
        #else
        false
        #endif
    }
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SparkReminders.Defaults.enabled) private var remindersEnabled = false
    /// The in-app language override (P9). Notification content is resolved at
    /// schedule time, so switching language would otherwise leave a fortnight
    /// of reminders queued in the old one.
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue

    /// Both of you, not just you — see `SparkStreak.sharedDays`. Filtering to
    /// your own author id, as this did, made 火花 a solo streak that climbed
    /// happily while she was away.
    private var status: SparkStreak.Status {
        let all = checkIns.map { (day: $0.day, authorID: $0.authorID) }
        let days = SparkStreak.sharedDays(all,
                                          mine: identity.authorID,
                                          theirs: ProfileStore.partnerAuthorID(in: context))
        // Your own days go in separately: the streak counts shared ones, but
        // whether the button still has something to do today is about you.
        let myDays = all.filter { $0.authorID == identity.authorID }.map(\.day)
        return SparkStreak.status(for: days, mine: myDays)
    }

    var body: some View {
        let status = self.status

        Button {
            Haptics.tap()
            if status.checkedInToday {
                // Never a dead tap (principle 7): once today is done the pill
                // becomes the way into the streak's details.
                showingSheet = true
            } else {
                CheckInStore.checkIn(in: context, authorID: identity.authorID)
                Haptics.success()
            }
        } label: {
            HStack(spacing: 8) {
                SparkFlame(isLit: status.checkedInToday, size: 22)
                label(for: status)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
        .accessibilityLabel(accessibilityLabel(for: status))
        .sheet(isPresented: $showingSheet) {
            SparkSheet(status: status)
        }
        // Top up the 14-day window: after a check-in (which must silence that
        // day), on foreground, and on a language change.
        .onChange(of: checkIns.count, initial: true) { _, _ in Task { await refreshReminders() } }
        .onChange(of: languageRaw) { _, _ in Task { await refreshReminders() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshReminders() }
        }
    }

    /// A zero streak is never shown as "0" — a number that says nothing and
    /// discourages. It reads as an invitation instead.
    private func label(for status: SparkStreak.Status) -> Text {
        if !status.checkedInToday {
            return Text("Check in")
        }
        // **Done your half.** Without this the pill had nothing to say between
        // your check-in and theirs, so the tap looked as though it had failed.
        if !status.sharedToday {
            return status.current == 0
                ? Text("Checked in")
                : Text("\(status.current) days — your half is done")
        }
        if status.current > 0 {
            return Text("\(status.current) days")
        }
        // Alive but not done today. Naming the risk is the whole point of the
        // distinction the streak rule draws.
        return Text("\(status.current) days — keep it going")
    }

    private func refreshReminders() async {
        await SparkReminders.reschedule(
            checkedIn: checkIns.filter { $0.authorID == identity.authorID }.map(\.day),
            enabled: remindersEnabled)
    }

    private func accessibilityLabel(for status: SparkStreak.Status) -> Text {
        status.checkedInToday
            ? Text("Checked in today. \(status.current) days.")
            : Text("Check in for today.")
    }
}
