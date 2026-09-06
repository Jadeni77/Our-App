import CoreGraphics

/// Turns a stream of `DragGesture` translations into heading changes.
///
/// **This is a separate, testable type for one reason: the bug it encodes the
/// fix for was invisible in a `View`.** `DragGesture.Value.translation` is the
/// total offset since the drag began, not the delta since the last callback,
/// and `FarshoreRootView` subtracted it on every `onChanged` — which
/// *integrates* the drag. Hold the finger still and the world keeps spinning.
/// The turn then scaled with how *long* a drag lasted rather than how far it
/// went (the same 200 pt swipe gave roughly 60° over half a second and 240°
/// over two) and doubled again on a 120 Hz ProMotion display, which delivers
/// twice the callbacks for the same finger movement. No sensitivity tuned on
/// one device was right on the other.
///
/// Buried in a gesture closure that was untestable and therefore untested. As
/// a value type it is neither, and the invariant that was broken — *the same
/// swipe turns you the same amount however many events it arrives in* — is
/// something a test can state directly.
///
/// Lives under `Rules/` rather than `UI/` because it is arithmetic, not a
/// view: it imports `CoreGraphics` for `CGFloat` and nothing else.
struct TurnTracker {
    /// Radians of yaw per point of horizontal drag.
    ///
    /// A rate over *distance*, not over events — which is the whole point.
    /// Roughly: a full swipe across an iPhone (≈390 pt) turns you about 112°,
    /// so a look-behind is three swipes. Deliberately slower than a shooter,
    /// because this is a walking game with a third-person follow camera, not
    /// a gun sight.
    ///
    /// Chosen to reproduce the *feel* of the integrating version it replaces
    /// so the owner's device tuning is not thrown away: that code multiplied
    /// by 0.00035 on every callback, and a 200 pt swipe over half a second at
    /// 60 Hz fired about 30 of them averaging ~100 pt each — ≈1.05 rad, i.e.
    /// ≈0.005 rad/pt. That equivalence held only at 60 Hz over half a second,
    /// which is exactly why it had to go, but it is the best available
    /// estimate of what "right" felt like on the owner's phone.
    static let radiansPerPoint: Double = 0.005

    private var lastTranslation: CGFloat = 0

    /// The heading change for this gesture callback, in radians. Negative
    /// because dragging right should swing the view right, which means
    /// rotating the *world* the other way.
    mutating func headingChange(translation: CGFloat) -> Double {
        let delta = translation - lastTranslation
        lastTranslation = translation
        return -Double(delta) * Self.radiansPerPoint
    }

    /// Call from `onEnded`. The next drag's translation restarts from zero, so
    /// a stale baseline would snap the heading by the whole of the previous
    /// drag on the first frame of the next one.
    mutating func end() {
        lastTranslation = 0
    }
}
