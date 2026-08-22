import PhotosUI
import SwiftUI

/// Editing **your own** profile.
///
/// The owner's objection, three times over: *"Why am I the one setting the name
/// and picture of my lover? That should be their profile, not mine."* Right —
/// and the answer starts here, with your half being yours to edit and reachable
/// where you would look for it: by tapping your own face.
///
/// Tapping it used to do nothing at all, which is its own bug. A face in the
/// corner of a screen looks like a button whether or not it is one.
struct MyProfileSheet: View {
    @Bindable var identity: CoupleIdentityStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItem: PhotosPickerItem?
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $identity.nameOne)
                    Button {
                        isPickerPresented = true
                    } label: {
                        HStack {
                            Text("Choose a photo")
                            Spacer()
                            if let image = identity.avatars[.one] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                            }
                        }
                    }
                } header: {
                    Text("You")
                } footer: {
                    // Says what is coming rather than leaving the asymmetry
                    // looking like an oversight.
                    Text("They set their own name and photo on their phone.")
                }
            }
            .navigationTitle(Text("Your profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem,
                          matching: .images)
            .onChange(of: pickedItem) {
                guard let item = pickedItem else { return }
                Task {
                    // A failure leaves the old picture in place, which is the
                    // right outcome and needs no message.
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        try? identity.setAvatar(data, for: .one)
                    }
                    pickedItem = nil
                }
            }
        }
    }
}
