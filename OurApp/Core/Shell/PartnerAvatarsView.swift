import SwiftUI

/// The two of us: avatar photos (or monogram circles) with names, a softly
/// pulsing heart between.
struct PartnerAvatarsView: View {
    let identity: CoupleIdentityStore
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 24) {
            avatar(for: .one, name: identity.nameOne, fallback: "Me")
            Text("💞")
                .font(.system(size: 34))
                .scaleEffect(pulse ? 1.15 : 0.95)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            avatar(for: .two, name: identity.nameTwo, fallback: "My love")
        }
    }

    private func avatar(for partner: Partner, name: String, fallback: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Group {
                if let image = identity.avatars[partner] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Monogram fallback: first character of the name, or a heart.
                    Text(name.isEmpty ? "♡" : String(name.prefix(1)))
                        .font(Theme.display(34))
                        .foregroundStyle(Theme.glow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.12))
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            if name.isEmpty {
                Text(fallback)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(name)
                    .font(Theme.display(18))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    PartnerAvatarsView(identity: CoupleIdentityStore())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
