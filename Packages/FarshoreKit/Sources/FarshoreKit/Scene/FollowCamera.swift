import Foundation
import SceneKit

/// A third-person rig that trails the player.
public final class FollowCamera: SCNNode {
    public static let distance: Double = 5.0
    public static let height: Double = 2.4

    /// Where the camera aims vertically, relative to the character's feet —
    /// chest height, not the feet themselves. **Declared as a reference to
    /// `PlayerNode.eyeHeight`, not a second literal**: this is the same
    /// "one decision, one place" lesson slice 1 paid for four times
    /// (textureScale, sunPeakIntensity, duskFraction, dayFogColor) — if this
    /// file restated `1.6` independently, retuning `PlayerNode.eyeHeight`
    /// alone would leave the camera aimed at the OLD height while the
    /// character's own notion of "eye level" moved, and the two would
    /// silently disagree the next time either was touched. A camera aimed
    /// at the ground puts the character at the top of the frame and the
    /// horizon out of shot — this is the constant that keeps that from
    /// happening now or after a later retune.
    public static let lookAtHeight: Double = PlayerNode.eyeHeight

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
