import SwiftData
import SwiftUI

/// A dot on the hub tile while today's question is unanswered by this phone's
/// owner.
///
/// The identity store comes from the environment rather than being built here.
/// Constructing one per view was two bugs at once: it never saw the owner being
/// set (a separate object from the one Settings mutates, and it only reads
/// defaults in `init`), and since Home rebuilds ~30×/s (H9) it re-read both
/// avatar files off disk on every frame.
struct DailyQuestionBadge: View {
    @Query(filter: QuestionAnswer.visible) private var answers: [QuestionAnswer]
    @Environment(CoupleIdentityStore.self) private var identity
    @Environment(\.scenePhase) private var scenePhase
    @State private var unanswered = false

    var body: some View {
        Group {
            if unanswered {
                Circle()
                    .fill(Theme.rose)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .offset(x: 4, y: -4)
                    .accessibilityLabel(Text("Not answered today"))
            } else {
                // An empty view gets no lifecycle modifiers, so the refresh
                // below would never install and the dot could never appear.
                Color.clear.frame(width: 1, height: 1)
            }
        }
        // The day is part of the key: without it, foregrounding the app the
        // morning after answering leaves yesterday's answer satisfying today,
        // and a once-a-day nudge never fires.
        .onChange(of: RefreshKey(updates: answers.map(\.updatedAt),
                                 owner: identity.me,
                                 day: SpecialDateSchedule.anchor(for: .now)),
                  initial: true) { _, _ in
            unanswered = DailyQuestionStore.isUnanswered(answers, by: identity.me)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            unanswered = DailyQuestionStore.isUnanswered(answers, by: identity.me)
        }
    }

    private struct RefreshKey: Equatable {
        let updates: [Date]
        let owner: Partner?
        let day: Date
    }
}
