#if DEBUG
import Foundation
import SwiftData

/// Headless screenshot verification can't tap, so `-seedDailyQuestion` claims
/// the phone for one partner and writes a couple of past answers — otherwise
/// the only reachable state is the "who is this phone" prompt.
///
/// DEBUG only, and it declines when the phone already has an owner, so it can
/// never overwrite a real choice.
enum DailyQuestionDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer,
                               identity: CoupleIdentityStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedDailyQuestion"),
              identity.me == nil else { return }

        identity.me = .one

        let context = ModelContext(container)
        let calendar = Calendar.current
        for daysAgo in [2, 5] {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            let question = DailyQuestionCatalog.question(on: day)
            DailyQuestionStore.write(daysAgo == 2 ? "The way the light came in this morning."
                                                  : "Getting the bikes out again.",
                                     in: context, questionID: question.id,
                                     day: day, author: .one)
        }
    }
}
#endif
