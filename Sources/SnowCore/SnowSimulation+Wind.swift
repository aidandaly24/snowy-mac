import Foundation

extension SnowSimulation {
    /// Lift exposed snow slowly into the same bounded granular field used by
    /// sweeping. Unplaced material stays on the original support.
    public func erodeSnowInWind(dt: Float, gust: Float = 1) {
        guard snowfall == .blizzard, ambientSnowfallEnabled, dt.isFinite, dt > 0,
              gust.isFinite, abs(wind.velocity.x) > 20 else { return }
        let power = min(1, (abs(wind.velocity.x) - 20) / 60)
        let depth = min(0.25, dt) * 0.75 * max(0, min(3, gust)) * power
        guard depth > 0 else { return }
        let side: Float = wind.velocity.x > 0 ? 1 : -1
        for drift in drifts {
            let surface = drift.surface
            var requested: Float = 0
            for i in drift.heights.indices {
                let x = Float(i) * drift.spacing
                if surface.isExposed(at: x) && surface.isSnowExposed(at: x) {
                    requested += min(depth, max(0, drift.heights[i] - 0.45)) * drift.spacing
                }
            }
            guard requested > 0.0001 else { continue }
            let localX: Float = side > 0 ? max(0, surface.width - 2) : min(2, surface.width)
            let source = SIMD2(surface.x + localX + side * 10,
                               surface.baseY(at: localX) - drift.height(at: localX) - 4)
            let point = SIMD2(max(2, min(size.x - 2, source.x)), max(2, min(size.y - 2, source.y)))
            let unplaced = looseSnow.add(mass: requested, at: point, direction: SIMD2(side, -0.3))
            let accepted = max(0, requested - unplaced)
            guard accepted > 0 else { continue }
            let fraction = accepted / requested
            for i in drift.heights.indices {
                let x = Float(i) * drift.spacing
                if surface.isExposed(at: x) && surface.isSnowExposed(at: x) {
                    drift.heights[i] -= min(depth, max(0, drift.heights[i] - 0.45)) * fraction
                }
            }
            meshDirty = true
            interactionDirty = true
        }
    }
}
