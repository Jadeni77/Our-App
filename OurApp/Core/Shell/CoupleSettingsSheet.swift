import PhotosUI
import SwiftUI

/// Edit names and avatar photos — the whole of "couple identity" (P6, local
/// settings only; the anniversary moved into Special Dates with P17).
/// PhotosPicker runs out-of-process, so no photo
/// library permission or Info.plist key is needed (non-obvious but true).
struct CoupleSettingsSheet: View {
    @Bindable var identity: CoupleIdentityStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickingFor: Partner?
    // Presentation is deliberately separate state from pickingFor: clearing the
    // target from the isPresented setter races the selection write and can drop
    // the picked photo (review ruling — do not merge these).
    @State private var isPickerPresented = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @State private var isPaired = SyncSecretStore.isPaired
    @State private var pairing = false


    private var lastSyncedLabel: Text {
        guard let last = SyncSettings.lastSynced() else { return Text("Not yet") }
        return Text(verbatim: last.formatted(.relative(presentation: .named)))
    }

    var body: some View {
        NavigationStack {
            Form {
                partnerSection(header: "Me", name: $identity.nameOne, partner: .one)
                partnerSection(header: "My love", name: $identity.nameTwo, partner: .two)

                Section {
                    if isPaired {
                        LabeledContent {
                            lastSyncedLabel
                        } label: {
                            Text("Last synced")
                        }
                        Button(role: .destructive) {
                            SyncSecretStore.clear()
                            isPaired = false
                        } label: {
                            Text("Forget the other phone")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            pairing = true
                        } label: {
                            Text("Pair our phones")
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    // Only what's true right now. There is no transport toggle:
                    // once paired, syncing is what the app does, and *how* is
                    // nobody's business but the app's.
                    Text(isPaired
                         ? "Your memories keep themselves in step whenever you're on the same wi-fi."
                         : "Pair once, and your memories keep themselves in step whenever you're on the same wi-fi.")
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
            .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) {
                guard let item = pickedItem, let partner = pickingFor else { return }
                Task {
                    // loadTransferable is async & throwing; failures just leave
                    // the old avatar in place (fail soft).
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        try? identity.setAvatar(data, for: partner)
                    }
                    pickedItem = nil
                    pickingFor = nil
                }
            }
        }
    }

    private func partnerSection(header: LocalizedStringKey, name: Binding<String>, partner: Partner) -> some View {
        Section(header) {
            TextField("Name", text: name)
            Button {
                pickingFor = partner
                isPickerPresented = true
            } label: {
                HStack {
                    Text("Choose a photo")
                    Spacer()
                    if let image = identity.avatars[partner] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    CoupleSettingsSheet(identity: CoupleIdentityStore())
}
