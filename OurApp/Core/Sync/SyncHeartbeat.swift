import SwiftData
import SwiftUI

/// Keeps sync running for as long as the app is on screen — **wherever you are
/// in it**.
///
/// Sync used to tick only when the couples Home screen appeared or came to the
/// foreground. Every other page was therefore frozen at whatever had arrived
/// before you opened it: sit on Daily Question while they answer and it never
/// filled in; sit on Memories and their photo never appeared. The records were
/// crossing correctly the whole time, which is what made it so convincing —
/// leaving the page and coming back "fixed" it, so it looked like the data was
/// missing rather than the screen being stale.
///
/// Co-op got its own poll when this bit there, which fixed one screen and left
/// the reasoning behind. This is that fix, made once, at the root, where a page
/// added tomorrow inherits it without anybody remembering to.
///
/// Foreground only: no timers survive backgrounding, no entitlements are
/// needed, and a phone in a pocket does nothing. When CloudKit's push is
/// working this becomes a backstop rather than the mechanism — but a backstop
/// that costs one request every few seconds while you are actively looking at
/// the app is worth having, because the alternative failure is silent.
struct SyncHeartbeat: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// Slow enough to be unnoticeable, fast enough that something they do while
    /// you are both looking lands while you are still looking.
    private let interval: Duration = .seconds(6)

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await SyncStack.tick(context: context)
                try? await Task.sleep(for: interval)
            }
        }
    }
}

extension View {
    /// Applied once, at the root.
    func syncingWhileVisible() -> some View { modifier(SyncHeartbeat()) }
}
