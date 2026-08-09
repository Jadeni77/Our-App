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
