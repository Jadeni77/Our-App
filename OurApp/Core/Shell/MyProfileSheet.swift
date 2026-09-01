import PhotosUI
import SwiftData
import SwiftUI

/// Editing **your own** profile — the record you own and they read.
///
/// The owner's objection, three times over: *"Why am I the one setting the name
/// and picture of my lover? That should be their profile, not mine."* This is
/// your half, and reachable where you would look for it: by tapping your face.
struct MyProfileSheet: View {
    let identity: CoupleIdentityStore

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var profile: Profile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: Binding(
                        get: { profile?.name ?? "" },
                        set: { newValue in
                            guard let profile else { return }
                            profile.name = newValue
                            profile.updatedAt = .now
                        }))

                    Button { isPickerPresented = true } label: {
                        HStack {
                            Text("Choose a photo")
                            Spacer()
                            if let image = ProfileStore.image(for: profile) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                            }
                        }
                    }

                    // **Yours to state, not theirs to guess.** It travels with
                    // your profile, so their phone words its sentences about
                    // you the way you asked rather than the way they assumed.
                    Picker(selection: Binding(
                        get: { profile?.voice ?? .they },
                        set: { newValue in
                            guard let profile else { return }
                            profile.pronoun = newValue.rawValue
                            profile.updatedAt = .now
                        })) {
                        ForEach(PartnerVoice.Pronoun.allCases) { pronoun in
                            Text(verbatim: pronoun.menuLabel).tag(pronoun)
                        }
                    } label: {
                        Text("Refer to me as")
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("They set their own name and photo on their phone.")
                }
            }
            .navigationTitle(Text("Your profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Done") }
                }
            }
            .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem,
                          matching: .images)
            .onChange(of: pickedItem) {
                guard let item = pickedItem, let profile else { return }
                Task {
                    // A failure leaves the old picture in place, which is the
                    // right outcome and needs no message.
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        ProfileStore.setPhoto(data, on: profile, in: context)
                    }
                    pickedItem = nil
                }
            }
            .task { profile = ProfileStore.mine(in: context, seedingFrom: identity) }
        }
    }

    private func save() {
        try? context.save()
        dismiss()
    }
}
