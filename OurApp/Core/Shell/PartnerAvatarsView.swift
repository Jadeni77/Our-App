import SwiftData
import SwiftUI

/// The two of us in the top corners (P8: reference-inspired structure):
/// avatar photos (or monogram circles) with names beneath.
struct PartnerAvatarsView: View {
    @State private var editingMine = false
    let identity: CoupleIdentityStore

    @Environment(\.modelContext) private var context
    /// Both halves come from records now — yours because you wrote it, theirs
    /// because they did. A name typed on the wrong phone was the whole
    /// complaint.
    @Query(filter: Profile.visible) private var profiles: [Profile]

    private var mine: Profile? { profiles.first { $0.authorID == LocalAuthor.id() } }
    private var theirs: Profile? {
        guard let partner = SyncSecretStore.partnerAuthorID() else { return nil }
        return profiles.first { $0.authorID == partner }
    }

    var body: some View {
        HStack(alignment: .top) {
            // **Yours is a button; theirs is not.** You edit your half, they
            // edit theirs — and a face that does nothing when tapped reads as
            // broken, which is how this was reported.
            Button {
                Haptics.tap()
                editingMine = true
            } label: {
                badge(for: .one, name: mine?.name ?? identity.nameOne,
                      image: ProfileStore.image(for: mine) ?? identity.avatars[.one],
                      fallback: "Me")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Your profile"))
            Spacer()
            // **No local fallback for their half.** Falling back to a name you
            // once typed for them is what made two paired phones disagree: one
            // showed "Jade" from its own defaults while the other, which had
            // never been told, showed the placeholder. Their name comes from
            // them or it is not known yet, and both phones say the same thing.
            badge(for: .two, name: theirs?.name ?? "",
                  image: ProfileStore.image(for: theirs),
                  fallback: "My love")
        }
        .sheet(isPresented: $editingMine) { MyProfileSheet(identity: identity) }
    }

    private func badge(for partner: Partner, name: String, image: UIImage?,
                       fallback: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Monogram fallback: first character of the name, or a heart.
                    Text(name.isEmpty ? "♡" : String(name.prefix(1)))
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.glow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.15))
                }
            }
            .frame(width: 66, height: 66)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)

            if name.isEmpty {
                Text(fallback)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text(name)
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    PartnerAvatarsView(identity: CoupleIdentityStore())
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
