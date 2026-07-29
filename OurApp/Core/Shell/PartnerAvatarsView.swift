import SwiftUI

/// The two of us in the top corners (P8: reference-inspired structure):
/// avatar photos (or monogram circles) with names beneath.
struct PartnerAvatarsView: View {
    let identity: CoupleIdentityStore

    var body: some View {
        HStack(alignment: .top) {
            badge(for: .one, name: identity.nameOne, fallback: "Me")
            Spacer()
            badge(for: .two, name: identity.nameTwo, fallback: "My love")
        }
    }

    private func badge(for partner: Partner, name: String, fallback: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image = identity.avatars[partner] {
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
