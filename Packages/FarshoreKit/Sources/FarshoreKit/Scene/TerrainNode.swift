import Foundation
import SceneKit

/// The whole island, as one node per chunk.
///
/// One node each rather than one merged mesh, because **rebuilding only what
/// changed is the performance claim this design rests on** — and you cannot
/// rebuild part of a merged mesh. `ChunkGrid.chunksTouched(byEditing:in:)`
/// decides the set; this only obeys it.
public final class TerrainNode: SCNNode {
    private let terrain: Terrain
    private let material: SCNMaterial
    private var chunkNodes: [ChunkIndex: SCNNode] = [:]

    public init(terrain: Terrain, material: SCNMaterial) {
        self.terrain = terrain
        self.material = material
        super.init()
        for x in 0..<terrain.chunkCountX {
            for z in 0..<terrain.chunkCountZ {
                let index = ChunkIndex(x: x, z: z)
                let node = SCNNode()
                chunkNodes[index] = node
                addChildNode(node)
                build(index)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Replaces geometry for exactly these chunks. Slice 3 calls it after an
    /// edit; slice 1 has no editing yet, so this is here to be *proven* rather
    /// than used — the spike's whole gate is that it stays cheap.
    public func rebuild(chunks: Set<ChunkIndex>) {
        for index in chunks { build(index) }
    }

    private func build(_ index: ChunkIndex) {
        guard let node = chunkNodes[index] else { return }
        let geometry = TerrainMeshBuilder.geometry(for: index, in: terrain)
        geometry.materials = [material]
        node.geometry = geometry
    }
}
