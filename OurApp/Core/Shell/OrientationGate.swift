import UIKit

/// Rotates the app for landscape modules (M13). Two masks cooperate here —
/// non-obvious, so spelled out: the Info.plist mask is the *allowed* set
/// (must include landscape or nothing below matters), while the app
/// delegate's mask is the *current* set iOS consults per rotation; the
/// geometry update is what actually turns an already-presented screen.
@MainActor
enum OrientationGate {
    static func enter(_ orientation: ModuleOrientation) {
        switch orientation {
        case .portrait:
            apply(mask: .portrait, turning: .portrait)
        case .landscape:
            apply(mask: .landscape, turning: .landscapeRight)
        }
    }

    static func exitToPortrait() {
        apply(mask: .portrait, turning: .portrait)
    }

    private static func apply(mask: UIInterfaceOrientationMask, turning: UIInterfaceOrientationMask) {
        AppDelegate.orientationMask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: turning))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// Exists solely to answer the per-rotation orientation question — SwiftUI
/// apps have no other hook for it. Everything else stays in the App struct.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Self.orientationMask }
    }
}
