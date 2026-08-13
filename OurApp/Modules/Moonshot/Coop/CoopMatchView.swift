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

    @Environment(\.modelContext) private var context
    @Environment(CoupleIdentityStore.self) private var identity
    @Query(filter: CoopMatch.live) private var matches: [CoopMatch]
    @State private var watchedNow = false
    @State private var playing = false

    private var match: CoopMatch? { matches.first { $0.levelID == level.id } }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(Text(verbatim: level.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if let match {
            if let turn = watchableTurn(in: match) {
                replay(of: turn, in: match)
            } else if CoopTurnRules.mayFling(identity.authorID, in: match) {
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

    private func watchableTurn(in match: CoopMatch) -> CoopTurn? {
        guard !watchedNow,
              CoopWatchedTurns.hasUnwatchedTurn(in: match, viewer: identity.authorID)
        else { return nil }
        return CoopMatchStore.turnToWatch(in: match, viewer: identity.authorID, context: context)
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
        }
    }

    private var waiting: some View {
        message(icon: "⏳", title: Text("Waiting for her"),
                detail: Text("You've taken your shot. It's with her now."))
    }

    private var start: some View {
        message(icon: "🤝", title: Text("Start together"),
                detail: Text("One of you flings, then the other. It keeps its place between you."))
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
