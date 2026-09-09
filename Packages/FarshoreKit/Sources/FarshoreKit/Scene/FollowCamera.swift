import Foundation
import SceneKit

/// A third-person rig that trails the player.
public final class FollowCamera: SCNNode {
    public static let distance: Double = 5.0
    public static let height: Double = 2.4

    /// Where the camera aims vertically, relative to the character's feet:
    /// **the middle of the chest**, at roughly 1.20 m on a 1.75 m body.
    ///
    /// This comment used to say "chest height" while the value was
    /// `PlayerNode.eyeHeight` — 1.60 m, the centre of the head. The camera
    /// stared at the character's forehead, which left the body occupying
    /// about 30% of frame height with the top half of the shot almost
    /// entirely empty sky. The comment described the framing that was wanted;
    /// the number delivered a different one, and nobody re-derived it.
    ///
    /// Derived from `CharacterProportions` rather than restated here, so
    /// retuning the body's height moves the aim point with it instead of
    /// leaving this pointing at where the chest used to be. That is the same
    /// "one decision, one place" lesson slice 1 paid for four times
    /// (textureScale, sunPeakIntensity, duskFraction, dayFogColor).
    public static let lookAtHeight: Double = CharacterProportions.chestHeight

    public override init() {
        super.init()
        let cameraNode = SCNCamera()
        IslandLook.configure(camera: cameraNode)
        camera = cameraNode
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public func follow(_ player: PlayerNode, heading: Double) {
        let behindX = player.worldX - sin(heading) * Self.distance
        let behindZ = player.worldZ - cos(heading) * Self.distance
        position = SCNVector3(Float(behindX),
                              player.position.y + Float(Self.height),
                              Float(behindZ))
        look(at: SCNVector3(Float(player.worldX),
                            player.position.y + Float(Self.lookAtHeight),
                            Float(player.worldZ)))
    }
}
