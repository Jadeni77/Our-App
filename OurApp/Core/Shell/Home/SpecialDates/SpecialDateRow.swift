import SwiftUI

/// One row on the Special Dates page: drawn icon, title, when it falls, and the
/// count. Passed rows dim and count up instead of down.
struct SpecialDateRow: View {
    let date: SpecialDate
    let status: SpecialDateSchedule.Status

    var body: some View {
        HStack(spacing: 12) {
            DateIconView(icon: date.icon)

            VStack(alignment: .leading, spacing: 2) {
                // User data — rendered verbatim, never routed through the catalog.
                Text(date.title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                subtitle
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)
            count
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 20)
        .opacity(isPassed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private var isPassed: Bool {
        if case .passed = status { return true }
        return false
    }

    /// A yearly date shows month + day and says so; a one-off shows its year.
    ///
    /// The formatted date and the separator are `verbatim` on purpose: a
    /// literal `Text("\(formatted) · ")` would auto-key `"%@ · "` into the
    /// String Catalog, adding a junk key that needs translating. Only the
    /// words go through the catalog.
    @ViewBuilder private var subtitle: some View {
        // Through localDay, never the raw instant: the anchor is a floating
        // civil day pinned at noon UTC, so formatting it directly would show
        // the wrong day anywhere past UTC+12.
        let day = SpecialDateSchedule.localDay(of: date.date)
        if date.repeatsYearly {
            Text(verbatim: day.formatted(.dateTime.month(.abbreviated).day()))
                + Text(verbatim: " · ")
                + Text("every year")
        } else {
            Text(verbatim: day.formatted(.dateTime.year().month(.abbreviated).day()))
        }
    }

    @ViewBuilder private var count: some View {
        switch status {
        case .today:
            Text("Today")
                .font(Theme.display(17))
                .foregroundStyle(.white)
        case .upcoming(let days):
            stack(days, unit: days == 1 ? "day" : "days")
        case .passed(let daysAgo):
            stack(daysAgo, unit: daysAgo == 1 ? "day ago" : "days ago")
        }
    }

    /// Ternaries of catalog keys are wrapped explicitly because only a literal
    /// `Text("…")` auto-keys into the String Catalog (same note as the counter).
    private func stack(_ number: Int, unit: LocalizedStringKey) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(number)")
                .font(Theme.display(22))
            Text(unit)
                .font(.system(size: 9, design: .rounded).weight(.semibold))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    VStack(spacing: 10) {
        SpecialDateRow(date: SpecialDate(title: "Her birthday",
                                         date: .now.addingTimeInterval(86_400 * 7),
                                         repeatsYearly: true, icon: .cake),
                       status: .upcoming(days: 7))
        SpecialDateRow(date: SpecialDate(title: "Kyoto trip", date: .now, icon: .plane),
                       status: .today)
        SpecialDateRow(date: SpecialDate(title: "First date",
                                         date: .now.addingTimeInterval(-86_400 * 1165),
                                         icon: .star),
                       status: .passed(daysAgo: 1165))
    }
    .padding(16)
    .frame(maxHeight: .infinity)
    .background(Theme.duskGradient)
}
