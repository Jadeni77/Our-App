import Foundation
import Testing
import UIKit
@testable import OurApp

@MainActor
struct CoupleIdentityTests {
    private func makeStore(suite: String, directory: URL) -> CoupleIdentityStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CoupleIdentityStore(defaults: defaults, directory: directory)
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: DaysTogether

    @Test func anniversaryDayItselfIsDayOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(DaysTogether.days(from: now, to: now) == 1)
    }

    @Test func nextCalendarDayIsDayTwo() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 23))!
        let next = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 1))!
        #expect(DaysTogether.days(from: start, to: next, calendar: calendar) == 2)
    }

    @Test func countsAcrossAYear() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2025, month: 7, day: 28))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28))!
        #expect(DaysTogether.days(from: start, to: now, calendar: calendar) == 366)
    }

    @Test func futureAnniversaryClampsToOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let future = now.addingTimeInterval(86_400 * 30)
        #expect(DaysTogether.days(from: future, to: now) == 1)
    }

    // MARK: CoupleIdentityStore

    /// The anniversary left this store with P17 (it is a `SpecialDate` record
    /// now, covered by AnniversaryMigrationTests). Names still round-trip here.
    @Test func namesRoundTrip() throws {
        let suite = "test.\(UUID().uuidString)"
        let dir = try tempDirectory()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = CoupleIdentityStore(defaults: defaults, directory: dir)
        store.nameOne = "小彬"
        store.nameTwo = "Mei"

        let reloaded = CoupleIdentityStore(defaults: defaults, directory: dir)
        #expect(reloaded.nameOne == "小彬")
        #expect(reloaded.nameTwo == "Mei")
    }

    /// The Keychain is process-wide, so each test brings its own storage —
    /// passed in, never swapped globally, because these suites run in parallel.
    private func isolated() -> InMemoryAuthorIDStorage { InMemoryAuthorIDStorage() }

    @Test func anIdentityFromBeforeTheKeychainIsCarriedOver() throws {
        let storage = isolated()
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("id-from-an-older-build", forKey: LocalAuthor.legacyDefaultsKey)

        // Regenerating here would orphan every record the install had written.
        #expect(LocalAuthor.id(defaults: defaults, storage: storage) == "id-from-an-older-build")
        #expect(storage.load() == "id-from-an-older-build")
    }

    @Test func anIdentitySurvivesTheAppBeingDeleted() throws {
        let storage = isolated()
        let first = LocalAuthor.id(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
                                   storage: storage)

        // Deleting the app takes the container — defaults, database, files —
        // and leaves the Keychain. A fresh, empty defaults stands in for that.
        let afterReinstall = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        afterReinstall.removePersistentDomain(forName: "test")
        #expect(LocalAuthor.id(defaults: afterReinstall, storage: storage) == first)
    }

    @Test func theAuthorIDIsGeneratedOnceAndThenStable() throws {
        let storage = isolated()
        let suite = "test.\(UUID().uuidString)"
        let dir = try tempDirectory()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Nobody is asked for it — a fresh install simply has one.
        let store = CoupleIdentityStore(defaults: defaults, directory: dir,
                                        authorStorage: storage)
        #expect(!store.authorID.isEmpty)

        let reloaded = CoupleIdentityStore(defaults: defaults, directory: dir,
                                           authorStorage: storage)
        #expect(reloaded.authorID == store.authorID)
    }

    @Test func twoInstallsGetDifferentAuthorIDs() throws {
        let dir = try tempDirectory()
        func freshInstall() throws -> String {
            // A genuinely separate phone: its own Keychain as well as its own
            // defaults. Sharing either would make this pass for the wrong reason.
            let suite = "test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return CoupleIdentityStore(defaults: defaults, directory: dir,
                                       authorStorage: isolated()).authorID
        }
        // The whole point: two phones can't collide the way two picks of the
        // same half could.
        #expect(try freshInstall() != freshInstall())
    }

    @Test func myOwnRecordsReadAsMineAndEverythingElseAsMyLove() throws {
        let storage = isolated()
        let suite = "test.\(UUID().uuidString)"
        let dir = try tempDirectory()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = CoupleIdentityStore(defaults: defaults, directory: dir,
                                        authorStorage: storage)
        #expect(store.slot(for: store.authorID) == .one)
        #expect(store.slot(for: UUID().uuidString) == .two)
        // Legacy values are somebody else until the migration rewrites them,
        // which is the safe direction: nothing is silently claimed as mine.
        #expect(store.slot(for: "one") == .two)
    }

    @Test func avatarPersistsToDiskAndReloads() throws {
        let suite = "test.\(UUID().uuidString)"
        let dir = try tempDirectory()
        let store = makeStore(suite: suite, directory: dir)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try store.setAvatar(image.jpegData(compressionQuality: 0.9)!, for: .one)
        #expect(store.avatars[.one] != nil)

        let reloaded = makeStore(suite: suite, directory: dir)
        #expect(reloaded.avatars[.one] != nil)
        #expect(reloaded.avatars[.two] == nil)
    }
}

/// Stands in for the Keychain, which is shared by the whole test process.
final class InMemoryAuthorIDStorage: AuthorIDStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var id: String?

    func load() -> String? {
        lock.lock(); defer { lock.unlock() }
        return id
    }

    func save(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        self.id = id
    }
}
