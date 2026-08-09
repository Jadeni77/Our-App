import SwiftUI

/// The two of us, above the day counter — drawn rather than the 💞 emoji
/// (principle 9). Two hearts in the couple's two accents, the second tucked
/// behind and turned slightly, so it reads as a pair rather than a sticker.
struct PairedHeartsView: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            HeartShape()
                .fill(Theme.violet)
                .frame(width: size * 0.72, height: size * 0.66)
                .rotationEffect(.degrees(14))
                .offset(x: size * 0.20, y: -size * 0.08)
                .opacity(0.9)

            HeartShape()
                .fill(Theme.rose)
                .frame(width: size * 0.84, height: size * 0.76)
                .rotationEffect(.degrees(-8))
                .offset(x: -size * 0.10, y: size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.violet.opacity(0.45), radius: size * 0.18)
        .accessibilityHidden(true)
    }
}

#Preview {
    PairedHeartsView(size: 60)
        .padding(40)
        .background(Theme.duskGradient)
}
