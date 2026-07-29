import SwiftUI

/// Animated "Together for N days". Counts up from 0 with an ease-out ramp on
/// appear; `.contentTransition(.numericText)` makes the digits roll rather
/// than crossfade (non-obvious SwiftUI nicety).
struct TogetherCounterView: View {
    let anniversary: Date
    @State private var shown = 0

    var body: some View {
        Text("Together for \(shown) days")
            .font(Theme.display(24))
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(shown)))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 22)
            .task { await countUp() }
    }

    private func countUp() async {
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
        Haptics.success()
    }
}

#Preview {
    TogetherCounterView(anniversary: .now.addingTimeInterval(-86_400 * 500))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
