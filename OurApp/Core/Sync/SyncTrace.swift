import Foundation

/// `-syncTrace <path>` appends a line per sync event to a file.
///
/// Headless runs have no console worth reading, and the interesting failures
/// here are timing ones — a tick that fired before discovery finished looks
/// identical to a transport that doesn't work.
enum SyncTrace {
    private static let queue = DispatchQueue(label: "sync.trace")

    static func write(_ line: String) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-syncTrace"),
              arguments.index(after: flag) < arguments.endIndex else { return }
        let url = URL(fileURLWithPath: arguments[arguments.index(after: flag)])
        let who = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        queue.async {
            let stamped = "[\(who)] \(line)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(stamped.utf8))
                try? handle.close()
            } else {
                try? Data(stamped.utf8).write(to: url)
            }
        }
        #endif
    }
}
