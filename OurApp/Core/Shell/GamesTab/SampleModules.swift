#if DEBUG
import SwiftUI

/// DEBUG-only placeholder modules (S4): with one real module, collection-
/// forming can't be exercised — these give the springboard enough tiles.
/// Never registered in RELEASE builds.
enum SampleModules {
    @MainActor static var descriptors: [ModuleDescriptor] {
        [descriptor("sample-stars", "✨"),
         descriptor("sample-dice", "🎲"),
         descriptor("sample-cards", "🃏")]
    }

    @MainActor private static func descriptor(_ id: String, _ emoji: String) -> ModuleDescriptor {
        ModuleDescriptor(id: id, name: "Sample game", emoji: emoji) {
            AnyView(SampleComingSoonView(emoji: emoji))
        }
    }
}

private struct SampleComingSoonView: View {
    let emoji: String

    var body: some View {
        ZStack {
            DreamyBackground()
            VStack(spacing: 12) {
                Text(emoji).font(.system(size: 56))
                Text("Coming soon")
                    .font(Theme.display(22))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .glassCard(cornerRadius: 28)
        }
    }
}
#endif
