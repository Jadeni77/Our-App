import SwiftUI

/// In-app language override (P9). Two mechanisms cooperate:
/// - SwiftUI `Text` follows the `\.locale` environment immediately — the shell
///   applies `localeOverride` at the root, so switching re-renders live.
/// - Bundle-based lookups (`String(localized:)`, `preferredLocalizations`) and
///   system formatters follow the app's `AppleLanguages` default, which
///   `applyToBundleDomain()` keeps in sync — fully effective on next launch.
/// When set to `.system`, the app follows the device language AND iOS's
/// per-app language setting (Settings → OurApp → Language), which writes the
/// same underlying default.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    static let storageKey = "app.languageOverride"

    var id: String { rawValue }

    /// nil = don't override; follow the system (device or per-app setting).
    var localeOverride: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }

    /// Language names are deliberately shown in their own language (never
    /// translated) — you must be able to find your way home from a language
    /// you can't read. Only "System" is a catalog key.
    @ViewBuilder
    var label: some View {
        switch self {
        case .system: Text("System")
        case .english: Text(verbatim: "English")
        case .simplifiedChinese: Text(verbatim: "简体中文")
        case .traditionalChinese: Text(verbatim: "繁體中文")
        }
    }

    /// Aligns the app's AppleLanguages default with the override so bundle
    /// lookups and formatters agree after the next launch. Clearing it hands
    /// control back to the device / iOS per-app setting.
    func applyToBundleDomain() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// The bundle `String(localized:)` lookups must use to agree with what's
    /// on screen *right now*: plain `String(localized:)` follows
    /// AppleLanguages, which only realigns at the next launch — so between an
    /// in-app language switch and that relaunch it hands back the *old*
    /// language. `.system` (or a missing lproj) falls through to `.main`.
    /// (`defaults` is injectable so tests never race each other over the
    /// real domain — suites run in parallel.)
    static func currentBundle(_ defaults: UserDefaults = .standard) -> Bundle {
        guard let raw = defaults.string(forKey: storageKey),
              let language = AppLanguage(rawValue: raw),
              language != .system,
              let path = Bundle.main.path(forResource: language.rawValue,
                                          ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}
