import Foundation
import SceneKit
import UIKit

/// The rendered food and water: one child node per `ForagePoint`, placed on
/// the terrain that produced them.
///
/// **No tests here**, for the same reason `CampfireNode` has none: this is a
/// picture of a fact `ForageFieldTests` and `ProximityRulesTests` already
/// pin (where the points are, which ones are available), and asserting on
/// the node tree would only pin the picture-drawing code, not the survival
/// behaviour it depicts.
public final class ForageNodes: SCNNode {
    /// Keyed by `ForagePoint.id` so `setAvailable(_:id:)` can hide exactly
    /// the one bush that was just picked without a linear search through
    /// every forage node in the scene — with dozens of points on the island,
    /// "just walk the child list" is the kind of cost that is invisible in a
    /// single call and expensive once `SurvivalDriver.take` is calling this
    /// every time it succeeds.
    private var nodesByID: [Int: SCNNode] = [:]

    public init(points: [ForagePoint], on terrain: Terrain) {
        super.init()
        for point in points {
            let child = Self.makeNode(for: point)
            child.position = SCNVector3(Float(point.x),
                                        Float(terrain.height(atX: point.x, z: point.z)),
                                        Float(point.z))
            addChildNode(child)
            nodesByID[point.id] = child
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Hides a picked bush, or shows a regrown one. A spring never calls this
    /// with `false` — `ForageField.isAvailable` always says yes for one — so
    /// the disc has no hidden state to reconcile; only berries actually pass
    /// `false` through here.
    public func setAvailable(_ available: Bool, id: Int) {
        nodesByID[id]?.isHidden = !available
    }

    private static func makeNode(for point: ForagePoint) -> SCNNode {
        switch point.kind {
        case .berries: return berriesNode()
        case .spring: return springNode()
        }
    }

    /// A small cluster of dark-green spheres, not one — a single sphere at
    /// this scale reads as a rock or a ball, and berries are a cluster of
    /// small round things, not one big round thing.
    private static func berriesNode() -> SCNNode {
        let node = SCNNode()
        let leaf = material(color: UIColor(red: 0.14, green: 0.30, blue: 0.12, alpha: 1), roughness: 0.8)
        let offsets: [SCNVector3] = [
            SCNVector3(0, 0.09, 0),
            SCNVector3(0.06, 0.06, 0.05),
            SCNVector3(-0.06, 0.06, -0.04),
            SCNVector3(0.04, 0.06, -0.07),
            SCNVector3(-0.05, 0.07, 0.06)
        ]
        for offset in offsets {
            let sphere = SCNSphere(radius: 0.08)
            sphere.firstMaterial = leaf
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = offset
            node.addChildNode(sphereNode)
        }
        return node
    }

    /// A flat, slightly reflective disc — low roughness rather than a
    /// texture, since a spring is a small, mostly still puddle rather than a
    /// body of water that needs its own shader.
    private static func springNode() -> SCNNode {
        let disc = SCNCylinder(radius: 0.85, height: 0.05)
        disc.firstMaterial = material(color: UIColor(red: 0.18, green: 0.42, blue: 0.52, alpha: 0.9),
                                      roughness: 0.08)
        let node = SCNNode(geometry: disc)
        node.position = SCNVector3(0, 0.025, 0)
        return node
    }

    /// Same PBR lighting model as the ground, the mannequin and the campfire
    /// — **not a second material style** (task brief).
    private static func material(color: UIColor, roughness: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        return material
    }
}
