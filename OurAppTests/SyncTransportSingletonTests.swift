import Foundation
import Testing
@testable import OurApp

/// The app gets **one** transport, and `SyncStack` is where it is chosen.
///
/// Home used to choose for itself, which meant a debug run pointed at a shared
/// folder had two at once: Home replicating through `FileCloudTransport` while
/// `SyncStack.tick` — the one co-op calls — handed its envelopes to
/// `LocalNetworkTransport`. Both phones pushed their turns into a channel the
/// other was not reading, so each kept its own match and both sat on "Waiting
/// for her" forever.
///
/// Nothing about that was visible from the code: each construction site was
/// individually correct, and the whole suite passed. The defect only existed in
/// the relationship between them, which is what this test holds still.
struct SyncTransportSingletonTests {
    private var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "OurApp")
    }

    @Test func onlySyncStackConstructsATransport() throws {
        let transports = ["FileCloudTransport(", "LocalNetworkTransport("]
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: appDirectory,
                                                   includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  // The stack itself, and each transport's own file, obviously
                  // name their own type.
                  !["SyncStack.swift", "FileCloudTransport.swift",
                    "LocalNetworkTransport.swift"].contains(url.lastPathComponent),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"),
                      transports.contains(where: line.contains)
                else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty,
                """
                A transport is built outside SyncStack at \(offenders.joined(separator: ", ")). \
                Ask SyncStack.transport instead — a second choice means two halves of \
                the app syncing over different channels, which fails silently.
                """)
    }

    /// And every screen that needs a sync goes through the same door.
    @Test func nobodyBuildsTheirOwnEngineOutsideTheShell() throws {
        var offenders: [String] = []
        let modules = appDirectory.appending(path: "Modules")
        let files = FileManager.default.enumerator(at: modules, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), line.contains("SyncEngine(") else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty,
                """
                A module builds its own SyncEngine at \(offenders.joined(separator: ", ")). \
                Use SyncStack.tick(context:), which shares the outbox, the cursor and \
                the transport with the rest of the app.
                """)
    }
}
