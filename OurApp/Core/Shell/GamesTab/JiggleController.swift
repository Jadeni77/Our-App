import Foundation
import Observation

/// What releasing the current drag would do (S2). `insertAt` indexes the
/// order with the dragged item removed — the same remove-then-insert basis
/// as `GamesLayoutStore.moveItem`.
enum DropIntent: Equatable {
    case none
    case reorder(insertAt: Int)
    case target(GamesLayout.ItemID)        // hovering, not yet armed
    case armedTarget(GamesLayout.ItemID)   // held ≥ armDelay — release acts
}

/// Edit-mode state plus the drag decision logic, kept free of view code so
/// the geometry rules are unit-testable (S1). Views feed it locations and
/// tile frames; it answers with a `DropIntent`.
@MainActor
@Observable
final class JiggleController {
    static let armDelay: TimeInterval = 0.4
    /// Fraction of a tile's size trimmed from each edge before it counts as
    /// a drop target — the ring left over reads as a reorder gap.
    private static let targetInset: CGFloat = 0.2

    var isEditing = false
    private(set) var draggedItem: GamesLayout.ItemID?
    private(set) var intent: DropIntent = .none

    private var hover: (target: GamesLayout.ItemID, since: Date)?

    func beginDrag(_ id: GamesLayout.ItemID) {
        draggedItem = id
        intent = .none
        hover = nil
    }

    func updateDrag(location: CGPoint,
                    frames: [GamesLayout.ItemID: CGRect],
                    order: [GamesLayout.ItemID],
                    now: Date) {
        guard let dragged = draggedItem else { return }
        let others = order.filter { $0 != dragged }

        // Only apps can land on things; collections never nest (games-springboard.md).
        if case .app = dragged,
           let target = others.first(where: { id in
               guard let frame = frames[id] else { return false }
               let inset = frame.insetBy(dx: frame.width * Self.targetInset,
                                         dy: frame.height * Self.targetInset)
               return inset.contains(location)
           }) {
            if let hover, hover.target == target {
                intent = now.timeIntervalSince(hover.since) >= Self.armDelay
                    ? .armedTarget(target) : .target(target)
            } else {
                hover = (target, now)
                intent = .target(target)
            }
            return
        }

        hover = nil
        intent = .reorder(insertAt: insertionIndex(location: location,
                                                   frames: frames, others: others))
    }

    func endDrag() -> DropIntent {
        let final = intent
        draggedItem = nil
        intent = .none
        hover = nil
        return final
    }

    /// Nearest tile center wins; landing after it in reading order (below its
    /// row, or right of it in the same row) inserts one slot later.
    private func insertionIndex(location: CGPoint,
                                frames: [GamesLayout.ItemID: CGRect],
                                others: [GamesLayout.ItemID]) -> Int {
        let centers: [(index: Int, center: CGPoint, height: CGFloat)] =
            others.enumerated().compactMap { index, id in
                guard let frame = frames[id] else { return nil }
                return (index, CGPoint(x: frame.midX, y: frame.midY), frame.height)
            }
        guard let nearest = centers.min(by: {
            hypot($0.center.x - location.x, $0.center.y - location.y) <
            hypot($1.center.x - location.x, $1.center.y - location.y)
        }) else { return 0 }

        let laterRow = location.y > nearest.center.y + nearest.height / 2
        let sameRowAfter = abs(location.y - nearest.center.y) <= nearest.height / 2
            && location.x > nearest.center.x
        return laterRow || sameRowAfter ? nearest.index + 1 : nearest.index
    }
}
