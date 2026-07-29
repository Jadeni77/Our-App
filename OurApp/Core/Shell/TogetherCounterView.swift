import SwiftUI

/// The home's hero (P8: reference-inspired structure): a small label line, a
/// huge day number that counts up with rolling digits, and the anniversary
/// date beneath. `.contentTransition(.numericText)` makes the digits roll
/// rather than crossfade (non-obvious SwiftUI nicety).
struct TogetherCounterView: View {
    let anniversary: Date
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("We've been together for")
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(shown)")
                    .font(Theme.display(74))
                    .contentTransition(.numericText(value: Double(shown)))
                // Ternary of two catalog keys — wrapped explicitly because only
                // literal Text("…") auto-keys into the String Catalog.
                Text(shown == 1 ? LocalizedStringKey("day") : LocalizedStringKey("days"))
                    .font(Theme.display(26))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .shadow(color: Theme.violet.opacity(0.5), radius: 16)

            Text(anniversary.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Together for \(shown) days"))
        .task(id: anniversary) { await countUp() }
    }

    private func countUp() async {
        let hadCounted = shown > 0
        shown = 0
        let target = DaysTogether.days(from: anniversary)
        let frames = 36
        for frame in 1...frames {
            // Ease-out cubic: fast start, gentle landing on the real number.
            let progress = 1 - pow(1 - Double(frame) / Double(frames), 3)
            let value = Int(Double(target) * progress)
            withAnimation(.snappy(duration: 0.05)) { shown = value }
            do {
                try await Task.sleep(for: .milliseconds(33))
            } catch {
                return // view disappeared — stop counting, no stray haptic
            }
        }
        guard !Task.isCancelled else { return }
        withAnimation(Theme.springy) { shown = target }
        if !hadCounted { Haptics.success() } // no repeat buzz on re-appear/edit
    }
}

#Preview {
    TogetherCounterView(anniversary: .now.addingTimeInterval(-86_400 * 500))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
