import SwiftUI
import SwiftData

@main
struct OurAppApp: App {
    /// Only for per-rotation orientation answers (OrientationGate, M13).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    /// In-app language override (P9): SwiftUI Text re-renders live when the
    /// \.locale environment changes; .system falls through to Locale.current
    /// (which already reflects iOS's per-app language setting).
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            // Cannot run without local storage; crashing at launch beats silent data loss.
            fatalError("Failed to create model container: \(error)")
        }
        AnniversaryMigration.runIfNeeded(in: container)
        AuthorIDMigration.runIfNeeded(in: container)
        #if DEBUG
        SpecialDatesDebugSeed.runIfRequested(in: container)
        MoonshotDebugSeed.runIfRequested(in: container)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                // A push arrives with no view hierarchy and therefore no
                // environment, so the container has to be reachable without
                // one. Set here because this is the only place that holds it
                // before any view exists.
                .task {
                    SharedContext.current = ModelContext(container)
                    if let target = await CoupleZone.syncTarget() {
                        SyncStack.cloudTarget = target
                        await CoupleSubscription.ensure(on: target.database)
                    }
                }
                .environment(
                    \.locale,
                    AppLanguage(rawValue: languageRaw)?.localeOverride ?? Locale.current
                )
        }
        .modelContainer(container)
    }
}
