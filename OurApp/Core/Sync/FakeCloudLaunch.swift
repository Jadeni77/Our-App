#if DEBUG
import Foundation

/// `-fakeCloud <path>` points this install at a folder both simulators can see.
/// Two simulators launched with the same path replicate to each other, which is
/// the only way to *watch* sync work before there is a CloudKit container.
///
/// DEBUG only, and absent by default — a release build has no transport at all
/// until slice D.
enum FakeCloudLaunch {
    static var directory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-fakeCloud"),
              arguments.index(after: flag) < arguments.endIndex else { return nil }
        return URL(fileURLWithPath: arguments[arguments.index(after: flag)])
    }
}
#endif
