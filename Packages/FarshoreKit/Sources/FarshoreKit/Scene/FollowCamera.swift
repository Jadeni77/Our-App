import Foundation
import SceneKit

/// A third-person rig that trails the player.
public final class FollowCamera: SCNNode {
    public static let distance: Double = 5.0
    public static let height: Double = 2.4

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
                            player.position.y + Float(PlayerNode.eyeHeight),
                            Float(player.worldZ)))
    }
}
