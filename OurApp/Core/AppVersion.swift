import Foundation

/// The running build's version line (P13): read from the bundle at runtime —
/// `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` are stamped by the build
/// and bumped only in release PRs, never typed into code.
enum AppVersion {
    /// e.g. "1.0 (1)"; a bundle missing the keys fails soft to dashes.
    static func display(from bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
        return "\(version) (\(build))"
    }
}
