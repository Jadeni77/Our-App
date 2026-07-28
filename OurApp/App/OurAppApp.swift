import SwiftUI
import SwiftData

@main
struct OurAppApp: App {
    private let container: ModelContainer

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
        }
        .modelContainer(container)
    }
}
