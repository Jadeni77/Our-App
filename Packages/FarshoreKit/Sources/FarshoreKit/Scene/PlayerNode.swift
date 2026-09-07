import Foundation
import SceneKit

/// Where the player is. **No physics body** — the ground is a height function,
/// so standing on it is one sample rather than a simulation. That is far
/// cheaper, exactly reproducible, and it cannot fall through the world.
public final class PlayerNode: SCNNode {
    /// Metres from the feet to the camera target.
    public static let eyeHeight: Double = 1.6

    public private(set) var worldX: Double = 0
    public private(set) var worldZ: Double = 0

    public override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public func place(x: Double, z: Double, on terrain: Terrain) {
        worldX = x
        worldZ = z
        settle(on: terrain)
    }

    public func step(input: SIMD2<Double>, heading: Double, dt: Double, terrain: Terrain) {
        let move = LocomotionRules.displacement(input: input, heading: heading, dt: dt)
        let travelled = sqrt(move.x * move.x + move.y * move.y)
        guard travelled > 0 else { return }

        let targetX = worldX + move.x
        let targetZ = worldZ + move.y
        let factor = LocomotionRules.slopeFactor(from: terrain.height(atX: worldX, z: worldZ),
                                                 to: terrain.height(atX: targetX, z: targetZ),
                                                 over: travelled)
        worldX += move.x * factor
        worldZ += move.y * factor
        settle(on: terrain)
    }

    private func settle(on terrain: Terrain) {
        let y = terrain.height(atX: worldX, z: worldZ)
        position = SCNVector3(Float(worldX), Float(y), Float(worldZ))
    }
}
