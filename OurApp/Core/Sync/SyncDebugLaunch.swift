#if DEBUG
import Foundation

/// Pairing needs a code typed on the other phone, which a headless run can't
/// do. `-pairOffer` writes this phone's code to the trace; `-pairWith <code>`
/// types one. Enough to prove the whole handshake without a finger.
enum SyncDebugLaunch {
    @MainActor
    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        SyncTrace.write("debug launch: \(arguments.filter { $0.hasPrefix("-pair") })")
        if arguments.contains("-pairOffer") {
            let code = await SyncStack.peers.beginPairing()
            SyncTrace.write("offering code \(code)")
        }
        if let flag = arguments.firstIndex(of: "-pairWith"),
           arguments.index(after: flag) < arguments.endIndex {
            let paired = await SyncStack.peers.pair(withCode: arguments[arguments.index(after: flag)])
            SyncTrace.write("pairWith: \(paired ? "paired" : "refused")")
        }
    }
}
#endif
