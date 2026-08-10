#if DEBUG
import Foundation
import SwiftData

/// Headless screenshot verification can't tap, so `-seedDailyQuestion` writes a
/// couple of past answers — otherwise the page has nothing but today's empty
/// prompt on it.
///
/// DEBUG only, and it declines when anything has been answered already, so it
/// can never sit on top of real answers.
enum DailyQuestionDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer,
                               identity: CoupleIdentityStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedDailyQuestion") else { return }

        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<QuestionAnswer>())) == 0 else { return }
        let calendar = Calendar.current
        for daysAgo in [2, 5] {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            let question = DailyQuestionCatalog.question(on: day)
            DailyQuestionStore.write(daysAgo == 2 ? "The way the light came in this morning."
                                                  : "Getting the bikes out again.",
                                     in: context, questionID: question.id,
                                     day: day, authorID: identity.authorID)
        }
    }
}
#endif
