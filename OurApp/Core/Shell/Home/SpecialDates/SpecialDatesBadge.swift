import SwiftData
import SwiftUI

/// The pill on Home's Special Dates tile. It runs its own query, so Home never
/// learns that `SpecialDate` exists — the entry hands this view over as an
/// opaque badge (`HubEntry.makeBadge`).
struct SpecialDatesBadge: View {
    @Query(filter: #Predicate<SpecialDate> { $0.deletedAt == nil })
    private var dates: [SpecialDate]

    var body: some View {
        if let status = SpecialDateSchedule.badge(for: dates) {
            label(for: status)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.indigo.opacity(0.85)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .offset(x: 6, y: -6)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder private func label(for status: SpecialDateSchedule.Status) -> some View {
        switch status {
        case .today:
            Text("Today")
        case .upcoming(let days):
            // Compact by design — the tile is small; the page has the full wording.
            Text(verbatim: "\(days)d")
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
