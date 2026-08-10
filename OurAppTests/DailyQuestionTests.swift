import Foundation
import SwiftData
import Testing
@testable import OurApp

struct DailyQuestionCatalogTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func thereAreSixtyQuestionsWithUniqueIDs() {
        let ids = DailyQuestionCatalog.all.map(\.id)
        #expect(ids.count == 60)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(""))
    }

    @Test func theSameDayAlwaysGivesTheSameQuestion() {
        // The whole point: two phones must agree with no coordination.
        let first = DailyQuestionCatalog.question(on: day(2026, 8, 9), calendar: calendar)
        let again = DailyQuestionCatalog.question(on: day(2026, 8, 9), calendar: calendar)
        #expect(first.id == again.id)
    }

    @Test func consecutiveDaysGiveDifferentQuestions() {
        let today = DailyQuestionCatalog.question(on: day(2026, 8, 9), calendar: calendar)
        let tomorrow = DailyQuestionCatalog.question(on: day(2026, 8, 10), calendar: calendar)
        #expect(today.id != tomorrow.id)
    }

    @Test func theCatalogWrapsAfterSixtyDays() {
        let start = day(2026, 8, 9)
        let wrapped = calendar.date(byAdding: .day, value: 60, to: start)!
        #expect(DailyQuestionCatalog.question(on: start, calendar: calendar).id
                == DailyQuestionCatalog.question(on: wrapped, calendar: calendar).id)
    }

    @Test func theTimeOfDayDoesNotChangeTheQuestion() {
        let morning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 1))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 23))!
        #expect(DailyQuestionCatalog.question(on: morning, calendar: calendar).id
                == DailyQuestionCatalog.question(on: night, calendar: calendar).id)
    }

    @Test func aDateBeforeTheOriginStillIndexesInsideTheArray() {
        // Swift's % keeps the dividend's sign; without the double-modulo this
        // would index off the front of the array and trap.
        let question = DailyQuestionCatalog.question(on: day(1998, 3, 4), calendar: calendar)
        #expect(DailyQuestionCatalog.all.contains { $0.id == question.id })
    }

    @Test func lookupByIDFindsEveryQuestionAndRejectsUnknownOnes() {
        for question in DailyQuestionCatalog.all {
            #expect(DailyQuestionCatalog.question(id: question.id)?.id == question.id)
        }
        #expect(DailyQuestionCatalog.question(id: "not-a-question") == nil)
    }
}

@MainActor
struct DailyQuestionStoreTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func writingAnAnswerStoresItForThatDayAndAuthor() throws {
        let context = try makeContext()
        let today = Date(timeIntervalSinceReferenceDate: 800_000_000)

        DailyQuestionStore.write("A cup of tea", in: context,
                                 questionID: "q01", day: today, authorID: "author-a")

        let found = DailyQuestionStore.answer(in: context, questionID: "q01",
                                              day: today, authorID: "author-a")
        #expect(found?.text == "A cup of tea")
        #expect(found?.authorID == "author-a")
    }

    @Test func editingTodayUpdatesTheRowRatherThanAddingOne() throws {
        let context = try makeContext()
        let today = Date(timeIntervalSinceReferenceDate: 800_000_000)

        DailyQuestionStore.write("First", in: context, questionID: "q01", day: today, authorID: "author-a")
        DailyQuestionStore.write("Second", in: context, questionID: "q01", day: today, authorID: "author-a")

        let all = try context.fetch(FetchDescriptor<QuestionAnswer>())
        #expect(all.count == 1)
        #expect(all.first?.text == "Second")
    }

    @Test func eachPartnerGetsTheirOwnRowForTheSameDay() throws {
        let context = try makeContext()
        let today = Date(timeIntervalSinceReferenceDate: 800_000_000)

        DailyQuestionStore.write("Mine", in: context, questionID: "q01", day: today, authorID: "author-a")
        DailyQuestionStore.write("Theirs", in: context, questionID: "q01", day: today, authorID: "author-b")

        #expect(try context.fetch(FetchDescriptor<QuestionAnswer>()).count == 2)
        #expect(DailyQuestionStore.answer(in: context, questionID: "q01",
                                          day: today, authorID: "author-b")?.text == "Theirs")
    }

    @Test func aDifferentDayIsADifferentRow() throws {
        let context = try makeContext()
        let today = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tomorrow = today.addingTimeInterval(86_400)

        DailyQuestionStore.write("Today", in: context, questionID: "q01", day: today, authorID: "author-a")
        DailyQuestionStore.write("Tomorrow", in: context, questionID: "q01", day: tomorrow, authorID: "author-a")

        #expect(try context.fetch(FetchDescriptor<QuestionAnswer>()).count == 2)
    }

    @Test func theDayIsStoredAsAFloatingCivilDay() throws {
        let context = try makeContext()
        let evening = Date(timeIntervalSinceReferenceDate: 800_000_000)

        DailyQuestionStore.write("Late", in: context, questionID: "q01", day: evening, authorID: "author-a")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let stored = try context.fetch(FetchDescriptor<QuestionAnswer>()).first!
        // Noon UTC, exactly as Special Dates anchors its dates (H8).
        #expect(utc.component(.hour, from: stored.day) == 12)
    }

    @Test func historyIsNewestFirstAndSkipsTombstones() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

        DailyQuestionStore.write("Older", in: context, questionID: "q01",
                                 day: base, authorID: "author-a")
        DailyQuestionStore.write("Newer", in: context, questionID: "q02",
                                 day: base.addingTimeInterval(86_400), authorID: "author-a")
        DailyQuestionStore.write("Gone", in: context, questionID: "q03",
                                 day: base.addingTimeInterval(2 * 86_400), authorID: "author-a")
        DailyQuestionStore.answer(in: context, questionID: "q03",
                                  day: base.addingTimeInterval(2 * 86_400),
                                  authorID: "author-a")?.deletedAt = .now
        try context.save()

        let history = try DailyQuestionStore.history(from: context)
        #expect(history.map(\.text) == ["Newer", "Older"])
    }
}

@MainActor
struct DailyQuestionBadgeRuleTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func anUnansweredDayNags() throws {
        #expect(DailyQuestionStore.isUnanswered([], by: "author-a"))
    }

    @Test func answeringTodaySilencesIt() throws {
        let context = try makeContext()
        let question = DailyQuestionCatalog.question()
        DailyQuestionStore.write("Done", in: context, questionID: question.id,
                                 day: .now, authorID: "author-a")
        let answers = try context.fetch(FetchDescriptor<QuestionAnswer>())
        #expect(DailyQuestionStore.isUnanswered(answers, by: "author-a") == false)
    }

    @Test func thePartnerAnsweringDoesNotSilenceIt() throws {
        let context = try makeContext()
        let question = DailyQuestionCatalog.question()
        DailyQuestionStore.write("Theirs", in: context, questionID: question.id,
                                 day: .now, authorID: "author-b")
        let answers = try context.fetch(FetchDescriptor<QuestionAnswer>())
        #expect(DailyQuestionStore.isUnanswered(answers, by: "author-a"))
    }

    @Test func yesterdaysAnswerDoesNotSilenceToday() throws {
        let context = try makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let question = DailyQuestionCatalog.question(on: yesterday)
        DailyQuestionStore.write("Old", in: context, questionID: question.id,
                                 day: yesterday, authorID: "author-a")
        let answers = try context.fetch(FetchDescriptor<QuestionAnswer>())
        #expect(DailyQuestionStore.isUnanswered(answers, by: "author-a"))
    }
}

struct DailyQuestionTimezoneTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    @Test func everyPhoneGetsTheSameQuestionForTheSameCivilDay() {
        // The guarantee the whole design rests on. The first version counted
        // days from a UTC instant re-localized through `startOfDay`, so every
        // timezone west of UTC was a day out — and every test ran in UTC, which
        // is precisely where that is invisible.
        let zones = ["Pacific/Kiritimati", "Asia/Shanghai", "Europe/London",
                     "America/New_York", "America/Los_Angeles", "Pacific/Midway"]
        for hour in [0, 9, 23] {
            var ids: Set<String> = []
            for zone in zones {
                let zoneCalendar = calendar(zone)
                let moment = zoneCalendar.date(
                    from: DateComponents(year: 2026, month: 8, day: 9, hour: hour))!
                ids.insert(DailyQuestionCatalog.question(on: moment,
                                                         calendar: zoneCalendar).id)
            }
            #expect(ids.count == 1, "phones disagreed at \(hour):00 — got \(ids)")
        }
    }
}
