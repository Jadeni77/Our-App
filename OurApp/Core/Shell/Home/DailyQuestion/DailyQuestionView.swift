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

    /// From the environment, not built here: Home owns the one store Settings
    /// mutates, and constructing a second would never see the owner change.
    @Environment(CoupleIdentityStore.self) private var identity
    @State private var editing = false
    @State private var showingSettings = false

    /// Everything derived from "what day is it", worked out **once** per body
    /// pass. As computed properties these were re-evaluated inside every
    /// `first`/`filter` closure — a `Calendar` construction per row, several
    /// times per render.
    private struct Today {
        let question: DailyQuestion
        let anchor: Date
        let mine: QuestionAnswer?
        let theirs: QuestionAnswer?
        let earlier: [QuestionAnswer]
    }

    private func resolve() -> Today {
        let question = DailyQuestionCatalog.question()
        let anchor = SpecialDateSchedule.anchor(for: .now)
        // "Mine" is this install's id; "theirs" is any other author (P18).
        // Before sync there is no other author, so `theirs` is simply nil —
        // no second half to name, and nothing to ask the owner about.
        let mine = identity.authorID

        func answer(matching isMine: Bool) -> QuestionAnswer? {
            answers.first {
                $0.questionID == question.id
                    && $0.day == anchor
                    && ($0.authorID == mine) == isMine
            }
        }

        return Today(question: question,
                     anchor: anchor,
                     mine: answer(matching: true),
                     theirs: answer(matching: false),
                     earlier: answers.filter { $0.day != anchor })
    }

    var body: some View {
        let today = resolve()

        ZStack {
            DreamyBackground(showsMoon: false)

            content(today)
        }
        .navigationTitle(Text("Daily Question"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $editing) {
            AnswerEditorSheet(question: today.question, existing: today.mine?.text ?? "") { text in
                DailyQuestionStore.write(text, in: context, questionID: today.question.id,
                                         day: .now, authorID: identity.authorID)
            }
        }
        .sheet(isPresented: $showingSettings) {
            CoupleSettingsSheet(identity: identity)
        }
    }

    private func content(_ today: Today) -> some View {
        List {
            Section {
                Text(today.question.text)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                Button {
                    Haptics.tap()
                    editing = true
                } label: {
                    slot(title: "Your answer", body: today.mine?.text,
                         placeholder: "Tap to answer")
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                slot(title: "Their answer", body: today.theirs?.text,
                     placeholder: "Waiting for them — this fills in when your phones can talk to each other")
                    .opacity(today.theirs == nil ? 0.6 : 1)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                header("Today")
            }
            .listRowBackground(Color.clear)

            if !today.earlier.isEmpty {
                Section {
                    ForEach(today.earlier) { pastRow($0) }
                } header: {
                    header("Earlier")
                }
                .listRowBackground(Color.clear)
            } else if today.mine == nil {
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
        .accessibilityElement(children: .combine)
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
        .accessibilityElement(children: .combine)
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
        .environment(CoupleIdentityStore())
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
