import SwiftData
import SwiftUI

/// Home's hero, now that the anniversary is a record rather than a setting
/// (P17): a single-row query feeding `TogetherCounterView`, or the prompt that
/// sends you to Special Dates to set one.
///
/// Deliberately its own view: Home's body re-renders with every motion sample
/// (~30/s), and keeping the query here means the fetch is the whole cost —
/// nothing derived, nothing recomputed (the H9 lesson).
struct HomeCounter: View {
    /// Sorted so that if a duplicate anniversary ever existed, this and the
    /// page's card would still agree on which row is *the* one — `ordered`
    /// resolves ties by earliest anchor, and `.first` of an unsorted query
    /// would not.
    @Query(filter: SpecialDate.anniversary, sort: \SpecialDate.date)
    private var anniversaries: [SpecialDate]

    let onSetUp: () -> Void

    var body: some View {
        if let anniversary = anniversaries.first {
            TogetherCounterView(
                anniversary: SpecialDateSchedule.localDay(of: anniversary.date))
        } else {
            Button(action: onSetUp) {
                Label {
                    Text("Set your anniversary")
                } icon: {
                    Image(systemName: "heart.circle.fill")
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: 22)
        }
    }
}

#Preview {
    HomeCounter(onSetUp: {})
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
