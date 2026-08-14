import SwiftData
import SwiftUI

/// One co-op level, in whichever state it's actually in.
///
/// Three states, and which one you get is **derived from the match** rather than
/// from navigation: there is a fling of hers you haven't seen, or it's your go,
/// or you're waiting. Deriving it means opening the app twice in a row can't
/// land you somewhere inconsistent with the record.
struct CoopMatchView: View {
    let level: MoonshotLevel

    /// **`LocalAuthor.id()`, never `@Environment(CoupleIdentityStore.self)`.**
    /// That store is declared on Home's `NavigationStack`; the Moonshot module
    /// mounts from the springboard and is not a child of it, so reading it here
    /// traps at launch. Daily Question shipped that crash once, I wrote a
    /// comment in `MoonshotHomeView` warning about it, and then wrote it again
    /// here anyway — hence this note, at the place someone would repeat it.

    @Environment(\.modelContext) private var context
    /// Not `CoopMatch.live`: a finished match has to stay visible here, or
    /// clearing a level makes it vanish from the query, drop back to the Start
    /// screen, and offer a button that correctly refuses to make a second match
    /// for a level that already has one — a button that does nothing.
    @Query(filter: CoopMatch.notDeleted) private var matches: [CoopMatch]
    @State private var watchedNow = false
    @State private var playing = false
    @State private var cannotStart = false
    /// Resolved in `.task`, **never in `body`**. Fetching during body
    /// evaluation invalidates the `@Query` that drives this view, which re-runs
    /// body, which fetches again — an infinite loop that freezes the app. It
    /// only bit once a match existed, which is why tapping Start was the
    /// trigger and everything before it felt fine.
    @State private var pendingWatch: CoopTurn?

    private var match: CoopMatch? { matches.first { $0.levelID == level.id } }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .task(id: match?.turnIndex) { refreshPendingWatch() }
        // Ask for a sync on arrival: this screen's whole purpose is to show
        // what she did, and Home isn't foregrounded while you're in here.
        .task {
            await SyncStack.tick(context: context)
            if let match { CoopMatchStore.reconcile(match, context: context) }
            refreshPendingWatch()
        }
        .onChange(of: watchedNow) { _, _ in refreshPendingWatch() }
        .navigationTitle(Text(verbatim: level.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if let match {
            if let turn = pendingWatch {
                // Ahead of the cleared state on purpose: if her shot was the
                // one that won it, she should get to watch it land before
                // being told the level is over.
                replay(of: turn, in: match)
            } else if match.finishedAt != nil {
                cleared
            } else if CoopTurnRules.mayFling(LocalAuthor.id(), in: match) {
                if playing {
                    CoopTurnGameView(level: level, match: match) {
                        playing = false
                        watchedNow = false
                    }
                } else {
                    yourTurn
                }
            } else {
                waiting
            }
        } else {
            start
        }
    }

    /// Starts the match. The board is the level, untouched, because nobody has
    /// flung yet — and whoever taps first takes the first turn, which needs no
    /// negotiation: the other phone learns it from the record.
    private func startMatch() {
        guard let partner = SyncSecretStore.partnerAuthorID() else {
            // Never a silent no-op (principle 7): a button that does nothing
            // is indistinguishable from a frozen app, which is exactly how
            // this was reported.
            cannotStart = true
            return
        }
        CoopMatchStore.start(levelID: level.id,
                             participants: [LocalAuthor.id(), partner],
                             firstTurn: CoopTurnRules.firstTurn(
                                 among: [LocalAuthor.id(), partner]),
                             board: BoardSnapshot(startOf: level),
                             in: context)
    }

    /// Recomputed when the match moves, off the body evaluation path.
    private func refreshPendingWatch() {
        guard let match, !watchedNow,
              CoopWatchedTurns.hasUnwatchedTurn(in: match, viewer: LocalAuthor.id())
        else {
            pendingWatch = nil
            return
        }
        pendingWatch = CoopMatchStore.turnToWatch(in: match, viewer: LocalAuthor.id(),
                                                  context: context)
    }

    @ViewBuilder
    private func replay(of turn: CoopTurn, in match: CoopMatch) -> some View {
        if let clip = FlingClipCodec.decode(turn.clip),
           let board = BoardSnapshotCodec.decode(match.boardState) {
            CoopReplayView(level: level, snapshot: board, clip: clip) {
                CoopWatchedTurns.markWatched(turn.index, of: match.id)
                watchedNow = true
            }
        } else {
            // An unplayable clip is not a lost turn: the board state is what the
            // game runs on, so it's marked watched and play continues.
            Color.clear.task {
                CoopWatchedTurns.markWatched(turn.index, of: match.id)
                watchedNow = true
            }
        }
    }

    private var yourTurn: some View {
        VStack(spacing: 20) {
            message(icon: "🎯", title: Text("Your turn"),
                    detail: Text("Take your shot — she'll see it when she next opens this."))
            Button {
                Haptics.tap()
                playing = true
            } label: {
                Text("Take your shot")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
            }
            .glassCard(cornerRadius: 22)
            if cannotStart {
                Text("Pair your phones again — this one doesn't know who it's paired with")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var cleared: some View {
        message(icon: "🌕", title: Text("Cleared together"),
                detail: Text("Nothing gloomy left standing. That one's yours."))
    }

    private var waiting: some View {
        message(icon: "⏳", title: Text("Waiting for her"),
                detail: Text("You've taken your shot. It's with her now."))
    }

    private var start: some View {
        VStack(spacing: 20) {
            message(icon: "🤝", title: Text("Start together"),
                    detail: Text("One of you flings, then the other. It keeps its place between you."))
            Button {
                Haptics.tap()
                startMatch()
            } label: {
                Text("Start")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 13)
            }
            .glassCard(cornerRadius: 22)
        }
    }

    private func message(icon: String, title: Text, detail: Text) -> some View {
        VStack(spacing: 12) {
            Text(verbatim: icon).font(.system(size: 40))
            title
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            detail
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
