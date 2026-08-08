import SwiftUI

/// One topic on Home's hub row (P16). An entry either goes somewhere or
/// explains why not — there is no separate "available" flag that could
/// disagree with a missing destination.
///
/// Deliberately **local to Home**, not a registered platform type: there is
/// exactly one hub today, and a registry for one consumer is the empty room
/// P2 forbids. It mirrors `ModuleDescriptor`'s shape (type-erased view
/// factories across a narrow seam) so promoting it later is a file move.
struct HubEntry: Identifiable {
    let id: String
    /// Localized via the String Catalog — the tile renders it directly.
    let name: LocalizedStringResource
    let emoji: String
    let kind: Kind
    /// The entry supplies its own badge, so Home never learns a sub-page's
    /// data types.
    let makeBadge: (@MainActor () -> AnyView)?

    enum Kind {
        case page(@MainActor () -> AnyView)
        /// Carries *why* it isn't here yet — a dimmed tile must never be a
        /// dead end (principle 7).
        case comingSoon(LocalizedStringResource)
    }

    init(id: String,
         name: LocalizedStringResource,
         emoji: String,
         kind: Kind,
         makeBadge: (@MainActor () -> AnyView)? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.kind = kind
        self.makeBadge = makeBadge
    }

    var isReady: Bool {
        if case .page = kind { return true }
        return false
    }
}

/// The value pushed onto Home's `NavigationStack`. A one-field struct rather
/// than a bare `String` so hub routing can't collide with a future
/// destination type that also happens to be a string.
struct HubRoute: Hashable {
    let entryID: String
}
