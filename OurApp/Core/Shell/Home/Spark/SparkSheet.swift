import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// The streak's details and its reminder. Opened by tapping the pill once
/// today is already done — so the pill is never a dead tap.
struct SparkSheet: View {
    let status: SparkStreak.Status

    @Environment(\.dismiss) private var dismiss
    @Environment(CoupleIdentityStore.self) private var identity
    @Environment(\.modelContext) private var context

    @AppStorage(SparkReminders.Defaults.enabled) private var enabled = false
    @AppStorage(SparkReminders.Defaults.hour) private var hour = SparkReminders.Defaults.defaultHour
    @AppStorage(SparkReminders.Defaults.minute) private var minute = 0

    @State private var authorization: UNAuthorizationStatus = .notDetermined

    private var isDenied: Bool {
        authorization == .denied
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text("\(status.current) days")
                    } label: {
                        Text("Now")
                    }
                    LabeledContent {
                        Text("\(status.longest) days")
                    } label: {
                        Text("Longest run")
                    }
                } footer: {
                    // Said here rather than on Home: it is the truth about the
                    // number, but it isn't what the pill is for.
                    Text("This counts your days. When our phones can talk to each other it'll count both.")
                }

                Section {
                    Toggle(isOn: $enabled) {
                        Text("Daily reminder")
                    }
                    .disabled(isDenied)

                    if enabled && !isDenied {
                        DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
                            Text("Time")
                        }
                    }

                    if isDenied {
                        // Never an enabled toggle that silently does nothing —
                        // that is the dead end the identity gate used to be.
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            Text("Turn on notifications in Settings")
                        }
                    }
                } footer: {
                    if isDenied {
                        Text("Notifications are off for this app.")
                    } else {
                        Text("One a day, and only until you've checked in.")
                    }
                }
            }
            .navigationTitle(Text("Your spark"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .task {
            authorization = await SparkReminders.authorizationStatus()
        }
        .onChange(of: enabled) { _, isOn in
            Task { await toggled(to: isOn) }
        }
        .onChange(of: hour) { _, _ in Task { await refresh() } }
        .onChange(of: minute) { _, _ in Task { await refresh() } }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        } set: { picked in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
            hour = parts.hour ?? SparkReminders.Defaults.defaultHour
            minute = parts.minute ?? 0
        }
    }

    private func toggled(to isOn: Bool) async {
        if isOn {
            // Permission is asked for here — at the moment it is wanted, with
            // the reason on screen — and nowhere else.
            let granted = await SparkReminders.requestAuthorization()
            authorization = await SparkReminders.authorizationStatus()
            if !granted {
                enabled = false
                return
            }
        }
        await refresh()
    }

    private func refresh() async {
        await SparkReminders.reschedule(
            checkedIn: CheckInStore.days(in: context, authorID: identity.authorID),
            enabled: enabled,
            at: DateComponents(hour: hour, minute: minute))
    }
}
