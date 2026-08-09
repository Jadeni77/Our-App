import SwiftData
import SwiftUI

/// The pill on Home's Special Dates tile. It runs its own query, so Home never
/// learns that `SpecialDate` exists — the entry hands this view over as an
/// opaque badge (`HubEntry.makeBadge`).
struct SpecialDatesBadge: View {
    @Query(filter: SpecialDate.visible) private var dates: [SpecialDate]
    @State private var status: SpecialDateSchedule.Status?

    var body: some View {
        Group {
            if let status {
                label(for: status)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.indigo.opacity(0.85)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Not decoration: an empty view gets no lifecycle modifiers, so
                // without something here the refresh below would never install,
                // `status` would never leave nil, and the badge could never
                // appear at all.
                Color.clear.frame(width: 1, height: 1)
            }
        }
        // Deriving this in `body` would be costly in a way that never shows up
        // in the simulator: Home reads `tilt.offset`, so its whole body — this
        // badge included, and `AnyView` stops SwiftUI skipping the subtree —
        // rebuilds with every motion sample, ~30×/s on a real phone. Each pass
        // would run a `Calendar.nextDate` search per yearly date. Recompute
        // only when the dates themselves change; keying on `updatedAt` catches
        // edits to a row, which comparing the array by identity would miss.
        .onChange(of: dates.map(\.updatedAt), initial: true) { _, _ in
            status = SpecialDateSchedule.badge(for: dates)
        }
    }

    @ViewBuilder private func label(for status: SpecialDateSchedule.Status) -> some View {
        switch status {
        case .today:
            Text("Today")
        case .upcoming(let days):
            // Compact by design — the tile is small; the page has the full
            // wording. Still a catalog key ("%lldd"), because "d" is an English
            // abbreviation: a Chinese reader expects 天.
            Text("\(days)d")
        case .passed:
            EmptyView()   // badge() never returns .passed; belt and braces.
        }
    }
}

#Preview {
    SpecialDatesBadge()
        .padding(40)
        .background(Theme.duskGradient)
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
