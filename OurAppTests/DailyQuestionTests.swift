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
