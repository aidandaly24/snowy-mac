import Foundation

extension SnowSimulation {
    public func addPlayfulSnow(at position: SIMD2<Float>, mass: Float) {
        guard position.x.isFinite, position.y.isFinite, mass.isFinite, mass > 0 else { return }
        let safe = SIMD2(max(1, min(size.x - 1, position.x)), max(1, min(size.y - 1, position.y)))
        retainRelease(SnowRelease(position: safe, height: 6, mass: min(500, mass)), in: &snowReleases)
        meshDirty = true
    }

    /// Knock a cap over its window's sides. Exhausted granular capacity leaves
    /// the unplaced area on its original cap instead of deleting snow.
    public func shakeSnow(fromSurfaceID id: UInt64) {
        guard let drift = drifts.first(where: { $0.surface.id == id }),
              id != DesktopSceneBuilder.groundID, !drift.surface.isDock else { return }
        looseSnow.beginFrame()
        for i in drift.heights.indices where drift.heights[i] > 0 {
            let mass = drift.heights[i] * drift.spacing
            let left = i < drift.heights.count / 2
            let x = left ? drift.surface.x - 8 : drift.surface.x + drift.surface.width + 8
            let point = SIMD2(max(1, min(size.x - 1, x)), max(1, drift.surface.y - 8))
            let unplaced = looseSnow.add(mass: mass, at: point, direction: SIMD2(left ? -1 : 1, 1))
            drift.heights[i] = max(0, drift.heights[i] - (mass - unplaced) / drift.spacing)
        }
        meshDirty = true
        interactionDirty = true
        rebuildMesh()
    }
}
