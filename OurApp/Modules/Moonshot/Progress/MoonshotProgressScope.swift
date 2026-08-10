import Foundation

/// Progress is **mirrored** (P20): the partner's rows live in the same store so
/// they can be shown, and they must never be counted as yours.
///
/// Before mirroring existed every `@Query` for progress was implicitly "mine",
/// because nothing else was ever in the store. Turning mirroring on quietly
/// changed what those queries mean — inflating star pools, unlocking rewards
/// the other person earned, and marking levels cleared that this phone never
/// cleared. None of that would have produced a compiler error.
///
/// So the scoping is spelled at every read site rather than assumed.
extension Array where Element == MoonshotLevelResult {
    var mine: [MoonshotLevelResult] { scoped(to: LocalAuthor.id()) }
    var theirs: [MoonshotLevelResult] { filter { $0.partnerID != LocalAuthor.id() } }
    func scoped(to authorID: String) -> [MoonshotLevelResult] {
        filter { $0.partnerID == authorID }
    }
}

extension Array where Element == MoonshotMoondustEntry {
    var mine: [MoonshotMoondustEntry] {
        let authorID = LocalAuthor.id()
        return filter { $0.partnerID == authorID }
    }
}

extension Array where Element == MoonshotCosmeticSetting {
    var mine: [MoonshotCosmeticSetting] {
        let authorID = LocalAuthor.id()
        return filter { $0.partnerID == authorID }
    }
}
