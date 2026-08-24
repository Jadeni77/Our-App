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
    @State private var isPaired = SyncSecretStore.isPaired

    var body: some View {
        NavigationStack {
            Form {
                // Only what you'd come here to *change*. Pairing lives on Home
                // where it's actually seen, and "last synced" was status
                // dressed as a setting — a stale timestamp worries you without
                // telling you anything you can act on. If sync is working,
                // their memories are simply there.
                if isPaired {
                    Section {
                        Button(role: .destructive) {
                            SyncSecretStore.clear()
                            isPaired = false
                        } label: {
                            Text("Forget the other phone")
                        }
                    } footer: {
                        Text("You'd pair again from the home screen.")
                    }
                }

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
