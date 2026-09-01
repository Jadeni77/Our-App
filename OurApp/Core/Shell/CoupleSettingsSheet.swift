import SwiftUI

/// What is genuinely a setting, and nothing else.
///
/// **Neither profile lives here any more.** Yours is behind your own face on
/// Home, where you would look for it; theirs is written on their phone and
/// simply arrives. This screen used to ask you to type your partner's name and
/// pick their photo, which was the wrong question asked of the wrong person.
///
/// Those fields stayed until a profile record existed to replace them —
/// removing them first would have left their half blank with no way to fill it.
struct CoupleSettingsSheet: View {
    let identity: CoupleIdentityStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                // **"Forget the other phone" used to live here, and is gone.**
                //
                // It cleared the pairing secret, and that stopped being a
                // disconnection the moment the app started deciding it knows
                // you two by the records you have exchanged. You could tap it
                // and still see their name, their check-ins and their memories,
                // still syncing. A destructive-looking button that changes
                // almost nothing is worse than no button.
                //
                // A real one would revoke the CloudKit share, stop the sync,
                // and delete what has arrived — and would have to say so before
                // doing it. That is a deliberate feature, not a settings row,
                // and nobody has asked for it yet. Re-inviting overwrites the
                // secret anyway, which covers pairing with the wrong device.

                Section("Language") {
                    Picker(selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { language in
                            language.label.tag(language.rawValue)
                        }
                    } label: {
                        Text("Language")
                    }
                    .onChange(of: languageRaw) {
                        // Keep bundle lookups/formatters aligned on next launch;
                        // the visible UI switches immediately via \.locale.
                        AppLanguage(rawValue: languageRaw)?.applyToBundleDomain()
                    }
                }

                Section {
                } footer: {
                    // Which build is on which phone (P13) — read at runtime,
                    // never hardcoded.
                    Text("OurApp \(AppVersion.display())")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle(Text("Our details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CoupleSettingsSheet(identity: CoupleIdentityStore())
}
