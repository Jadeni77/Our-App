import Foundation
import SwiftData

/// How the app refers to the other person.
///
/// The copy used to say "her" everywhere, which is an assumption the app has no
/// business making about anybody's partner. It is also avoidable: most of the
/// time the right word is simply their name.
///
/// So `label` prefers the name, and falls back to the pronoun only when no name
/// has been set. Every sentence that uses it takes the **object form only** —
/// "Waiting for Yuki", "Waiting for them" — because one grammatical form is one
/// that cannot come out wrong. Possessives ("her turn" / "their turn") and
/// subject agreement ("she is" / "they are") differ per pronoun in English and
/// would need a variant of every sentence for every choice.
///
/// A free enum rather than the `CoupleIdentityStore`: Moonshot mounts from the
/// springboard and is not a child of Home's `NavigationStack`, so reading that
/// store from the environment there traps at launch. This reads the same
/// defaults with no environment at all.
enum PartnerVoice {
    enum Pronoun: String, CaseIterable, Identifiable {
        case she, he, they
        var id: String { rawValue }

        /// The object form — "waiting for *her*".
        var objectForm: String {
            switch self {
            case .she: String(localized: "her", comment: "Object pronoun for a partner")
            case .he: String(localized: "him", comment: "Object pronoun for a partner")
            case .they: String(localized: "them", comment: "Object pronoun for a partner")
            }
        }

        /// What the picker shows.
        var menuLabel: String {
            switch self {
            case .she: String(localized: "She / her")
            case .he: String(localized: "He / him")
            case .they: String(localized: "They / them")
            }
        }
    }

    private static let key = "partnerPronoun"

    /// Defaults to `they`, which is the choice that is never wrong about
    /// someone whose preference the app has not been told.
    static func pronoun(defaults: UserDefaults = .standard) -> Pronoun {
        defaults.string(forKey: key).flatMap(Pronoun.init(rawValue:)) ?? .they
    }

    static func setPronoun(_ pronoun: Pronoun, defaults: UserDefaults = .standard) {
        defaults.set(pronoun.rawValue, forKey: key)
    }

    /// What to call the other person, **from their own profile when they have
    /// sent one**.
    ///
    /// Their name and pronoun are theirs to state. The stored fallback below is
    /// what your phone assumed before they had said anything, and it stays only
    /// for that gap — including the whole of the time before you have paired.
    @MainActor
    static func label(from profile: Profile?, defaults: UserDefaults = .standard) -> String {
        if let profile {
            let stated = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return stated.isEmpty ? profile.voice.objectForm : stated
        }
        return label(defaults: defaults)
    }

    /// The form every screen should use: ask the store, which knows whether
    /// they have introduced themselves yet.
    @MainActor
    static func label(in context: ModelContext) -> String {
        label(from: ProfileStore.partner(in: context))
    }

    /// The last resort, from before profiles existed. Kept for the gap before
    /// they have sent one — which includes all of the time before you pair.
    static func label(defaults: UserDefaults = .standard) -> String {
        let name = (defaults.string(forKey: CoupleIdentityStore.Keys.nameTwo) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? pronoun(defaults: defaults).objectForm : name
    }
}
