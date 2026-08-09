import SwiftData
import SwiftUI

/// Hub sub-page: today's question, both slots, and every past answer.
///
/// Wears the sub-page chrome contract — dreamy background with no tilt parallax
/// and no moon (H16), hidden toolbar background, inline title, tab bar visible.
struct DailyQuestionView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: QuestionAnswer.visible, sort: \QuestionAnswer.day, order: .reverse)
    private var answers: [QuestionAnswer]

    @State private var identity = CoupleIdentityStore()
    @State private var editing = false

    private var today: DailyQuestion { DailyQuestionCatalog.question() }
    private var todayAnchor: Date { SpecialDateSchedule.anchor(for: .now) }

    /// Read from the queried array rather than re-fetching: `body` runs often
    /// enough that a fetch per computed property is wasted work, and `@Query`
    /// already holds every visible answer.
    private func answer(by author: Partner?) -> QuestionAnswer? {
        guard let author else { return nil }
        return answers.first {
            $0.questionID == today.id
                && $0.day == todayAnchor
                && $0.authorID == author.rawValue
        }
    }

    private var mine: QuestionAnswer? { answer(by: identity.me) }

    private var theirs: QuestionAnswer? {
        guard let me = identity.me else { return nil }
        return answer(by: me == .one ? .two : .one)
    }

    private var earlier: [QuestionAnswer] {
        answers.filter { $0.day != todayAnchor }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            if identity.me == nil {
                whoIsThis
            } else {
                content
            }
        }
        .navigationTitle(Text("Daily Question"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $editing) {
            AnswerEditorSheet(question: today, existing: mine?.text ?? "") { text in
                guard let me = identity.me else { return }
                DailyQuestionStore.write(text, in: context, questionID: today.id,
                                         day: .now, author: me)
            }
        }
    }

    /// Fail-soft (principle 7): an answer with no author would be unattributable
    /// the moment sync arrives, so ask first rather than guess.
    private var whoIsThis: some View {
        VStack(spacing: 14) {
            Text(verbatim: "💬").font(.system(size: 38))
            Text("Tell us who this phone belongs to first")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var content: some View {
        List {
            Section {
                Text(today.text)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                mineSlot
                theirsSlot
            } header: {
                header("Today")
            }
            .listRowBackground(Color.clear)

            if !earlier.isEmpty {
                Section {
                    ForEach(earlier) { pastRow($0) }
                } header: {
                    header("Earlier")
                }
                .listRowBackground(Color.clear)
            } else if mine == nil {
                Text("No answers yet — today is a good place to start")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var mineSlot: some View {
        Button {
            Haptics.tap()
            editing = true
        } label: {
            slot(title: "Your answer", body: mine?.text, placeholder: "Tap to answer")
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var theirsSlot: some View {
        slot(title: "Their answer", body: theirs?.text,
             placeholder: "Waiting for them — this fills in when your phones can talk to each other")
            .opacity(theirs == nil ? 0.6 : 1)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func slot(title: LocalizedStringKey,
                      body text: String?,
                      placeholder: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)
            if let text, !text.isEmpty {
                Text(text)                       // user data, verbatim
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text(placeholder)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 20)
    }

    private func pastRow(_ answer: QuestionAnswer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: SpecialDateSchedule.localDay(of: answer.day)
                .formatted(.dateTime.year().month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            if let question = DailyQuestionCatalog.question(id: answer.questionID) {
                Text(question.text)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(answer.text)                     // user data, verbatim
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(.white.opacity(0.75))
            .textCase(.uppercase)
    }
}

#Preview {
    NavigationStack { DailyQuestionView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
