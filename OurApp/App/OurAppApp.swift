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
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(
                    \.locale,
                    AppLanguage(rawValue: languageRaw)?.localeOverride ?? Locale.current
                )
        }
        .modelContainer(container)
    }
}
