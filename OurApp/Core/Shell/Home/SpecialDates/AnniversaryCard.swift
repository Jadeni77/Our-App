import SwiftUI

/// The anniversary's own card at the top of Special Dates (layout A, P17).
///
/// It repeats Home's day count on purpose — the owner's call — but earns its
/// place by carrying the two things Home doesn't: the day we started, and how
/// long until the next one.
struct AnniversaryCard: View {
    /// nil until an anniversary has been set.
    let entry: SpecialDateSchedule.Entry?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let entry {
                    Text("We've been together for")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    daysTogether(for: entry.date)
                    detail(for: entry)
                } else {
                    Text(verbatim: "💞").font(.system(size: 30))
                    Text("Set the day we started")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .glassCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }

    private func daysTogether(for date: SpecialDate) -> some View {
        let days = DaysTogether.days(from: SpecialDateSchedule.localDay(of: date.date))
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(days)")
                .font(Theme.display(38))
            Text(days == 1 ? "day" : "days")
                .font(Theme.display(15))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private func detail(for entry: SpecialDateSchedule.Entry) -> some View {
        let started = SpecialDateSchedule.localDay(of: entry.date.date)
            .formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        VStack(spacing: 2) {
            Text("since \(started)")
            switch entry.status {
            case .today:
                Text("The next one is today")
            case .upcoming(let days):
                Text("\(days) days until the next one")
            case .passed:
                // A yearly date never reports passed; nothing sensible to say.
                EmptyView()
            }
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.7))
    }
}

#Preview {
    VStack(spacing: 14) {
        AnniversaryCard(
            entry: (SpecialDate(title: "", date: .now.addingTimeInterval(-86_400 * 1165),
                                repeatsYearly: true, isAnniversary: true),
                    .upcoming(days: 209)),
            action: {})
        AnniversaryCard(entry: nil, action: {})
    }
    .padding(16)
    .frame(maxHeight: .infinity)
    .background(Theme.duskGradient)
}
