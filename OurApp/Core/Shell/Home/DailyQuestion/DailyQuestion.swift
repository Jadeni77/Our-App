import Foundation

/// One question, identified by a stable id so an answer keeps naming the same
/// question even as the catalog grows (the `cuisineID` precedent, F6).
struct DailyQuestion: Identifiable, Equatable {
    let id: String
    let text: LocalizedStringResource
}

/// The sixty questions, and the rule that picks today's.
enum DailyQuestionCatalog {
    /// Today's question is a pure function of the calendar day, counted from
    /// `Date`'s own reference date. Deliberately stateless: a sequence counter
    /// or a "next" button would diverge between two installs, and the two of us
    /// would end up answering different questions on the same day.
    static func question(on day: Date = .now, calendar: Calendar = .current) -> DailyQuestion {
        let origin = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let today = calendar.startOfDay(for: day)
        let elapsed = calendar.dateComponents([.day], from: origin, to: today).day ?? 0
        // Swift's % keeps the sign of the dividend; dates before 2001 would
        // otherwise index backwards off the front of the array.
        let index = ((elapsed % all.count) + all.count) % all.count
        return all[index]
    }

    static func question(id: String) -> DailyQuestion? {
        all.first { $0.id == id }
    }

    static let all: [DailyQuestion] = [
        DailyQuestion(id: "q01", text: "What made you smile today?"),
        DailyQuestion(id: "q02", text: "What is something small I do that you love?"),
        DailyQuestion(id: "q03", text: "Where should we go next, if money didn't matter?"),
        DailyQuestion(id: "q04", text: "What were you like as a child?"),
        DailyQuestion(id: "q05", text: "What is your favourite memory of us so far?"),
        DailyQuestion(id: "q06", text: "What are you looking forward to this week?"),
        DailyQuestion(id: "q07", text: "What is something you want to get better at?"),
        DailyQuestion(id: "q08", text: "What song reminds you of me?"),
        DailyQuestion(id: "q09", text: "What did you worry about today?"),
        DailyQuestion(id: "q10", text: "What is your idea of a perfect lazy day?"),
        DailyQuestion(id: "q11", text: "What is the bravest thing you have ever done?"),
        DailyQuestion(id: "q12", text: "What food would you never get tired of?"),
        DailyQuestion(id: "q13", text: "When did you last feel really proud of yourself?"),
        DailyQuestion(id: "q14", text: "What do you think I am best at?"),
        DailyQuestion(id: "q15", text: "What would you like us to do more of?"),
        DailyQuestion(id: "q16", text: "What is something you have changed your mind about?"),
        DailyQuestion(id: "q17", text: "Which place from your childhood do you miss?"),
        DailyQuestion(id: "q18", text: "What is the nicest thing anyone has said to you?"),
        DailyQuestion(id: "q19", text: "How do you like to be comforted when you are sad?"),
        DailyQuestion(id: "q20", text: "What is something you find beautiful that others might not?"),
        DailyQuestion(id: "q21", text: "What did you dream about recently?"),
        DailyQuestion(id: "q22", text: "What is a habit of mine you have quietly picked up?"),
        DailyQuestion(id: "q23", text: "What would your perfect morning look like?"),
        DailyQuestion(id: "q24", text: "Who do you miss right now?"),
        DailyQuestion(id: "q25", text: "What is something you want to tell me but keep forgetting?"),
        DailyQuestion(id: "q26", text: "What is the best gift you have ever been given?"),
        DailyQuestion(id: "q27", text: "What makes you feel most like yourself?"),
        DailyQuestion(id: "q28", text: "What is a small thing that instantly ruins your mood?"),
        DailyQuestion(id: "q29", text: "What did you believe as a child that turned out to be wrong?"),
        DailyQuestion(id: "q30", text: "What is something we should try together this month?"),
        DailyQuestion(id: "q31", text: "What is the last thing that made you laugh out loud?"),
        DailyQuestion(id: "q32", text: "Where do you feel most at peace?"),
        DailyQuestion(id: "q33", text: "What is a compliment you would like to hear more often?"),
        DailyQuestion(id: "q34", text: "What did you want to be when you grew up?"),
        DailyQuestion(id: "q35", text: "What is something you are grateful for today?"),
        DailyQuestion(id: "q36", text: "What is the hardest thing about this week?"),
        DailyQuestion(id: "q37", text: "What smell takes you straight back somewhere?"),
        DailyQuestion(id: "q38", text: "What do you hope we are doing five years from now?"),
        DailyQuestion(id: "q39", text: "What is something you would like to forgive yourself for?"),
        DailyQuestion(id: "q40", text: "What is your favourite thing about where we live?"),
        DailyQuestion(id: "q41", text: "What is a story about your family you love telling?"),
        DailyQuestion(id: "q42", text: "When did you last surprise yourself?"),
        DailyQuestion(id: "q43", text: "What is something you would like to learn together?"),
        DailyQuestion(id: "q44", text: "What is your most useless talent?"),
        DailyQuestion(id: "q45", text: "What is something I could do to make tomorrow easier for you?"),
        DailyQuestion(id: "q46", text: "What do you think about right before falling asleep?"),
        DailyQuestion(id: "q47", text: "What is a rule you grew up with that you have kept?"),
        DailyQuestion(id: "q48", text: "What is the kindest thing you have seen a stranger do?"),
        DailyQuestion(id: "q49", text: "What would you do with a completely free weekend?"),
        DailyQuestion(id: "q50", text: "What is something you own that you would never replace?"),
        DailyQuestion(id: "q51", text: "What is a fear you have mostly grown out of?"),
        DailyQuestion(id: "q52", text: "What is your favourite way to spend an evening in?"),
        DailyQuestion(id: "q53", text: "What is a moment you wish you could live again?"),
        DailyQuestion(id: "q54", text: "What is something you are curious about lately?"),
        DailyQuestion(id: "q55", text: "What do you need more of right now?"),
        DailyQuestion(id: "q56", text: "What is a tiny thing that made today better?"),
        DailyQuestion(id: "q57", text: "What is something you would like us to stop doing?"),
        DailyQuestion(id: "q58", text: "Which season feels most like you?"),
        DailyQuestion(id: "q59", text: "What is a promise you would like to make to yourself?"),
        DailyQuestion(id: "q60", text: "What do you love most about us?"),
    ]
}
