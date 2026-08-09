import SwiftData
import SwiftUI

/// A dot on the hub tile while today's question is unanswered by this phone's
/// owner. Home rebuilds ~30×/s (H9), so the answer set is compared on change,
/// never recomputed per frame.
struct DailyQuestionBadge: View {
    @Query(filter: QuestionAnswer.visible) private var answers: [QuestionAnswer]
    @State private var unanswered = false
    @State private var identity = CoupleIdentityStore()

    var body: some View {
        Group {
            if unanswered {
                Circle()
                    .fill(Theme.rose)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .offset(x: 4, y: -4)
            } else {
                // An empty view gets no lifecycle modifiers, so the refresh
                // below would never install and the dot could never appear.
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .onChange(of: answers.map(\.updatedAt), initial: true) { _, _ in
            guard let me = identity.me else {
                unanswered = false      // nothing to nag about before setup
                return
            }
            let today = SpecialDateSchedule.anchor(for: .now)
            let questionID = DailyQuestionCatalog.question().id
            unanswered = !answers.contains {
                $0.questionID == questionID && $0.day == today && $0.authorID == me.rawValue
            }
        }
    }
}
