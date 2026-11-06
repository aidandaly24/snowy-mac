import XCTest
@testable import SnowCore

final class LightSnowCatchTests: XCTestCase {
    private func wire(id: UInt64 = 123, y: Float = 150, fraction: Float = 0.2) -> Surface {
        WireSnowSupport.build(id: id, points: [SIMD2(0, y), SIMD2(800, y)], size: SIMD2(800, 600),
                              occluders: [], catchFraction: fraction)!
    }

    private var floor: Surface { Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 600, width: 800) }

    func testTwentyPercentCatchLetsTheOtherFlakesLandOnTheFloorAcrossManyBuckets() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0), seed: 42)
        simulation.updateSurfaces([wire(), floor])
        var caught = 0
        var onFloor = 0
        for _ in 0..<2000 {
            simulation.clear()
            let particle = SnowParticle(position: SIMD2(700, 610), velocity: SIMD2(600, 610),
                                        radius: 1, opacity: 1, phase: 0, remainingLife: 1)
            XCTAssertTrue(simulation.land(from: SIMD2(100, 0), particle: particle))
            if simulation.drifts[0].heights.contains(where: { $0 > 0 }) { caught += 1 }
            if simulation.drifts[1].heights.contains(where: { $0 > 0 }) { onFloor += 1 }
        }
        XCTAssertEqual(caught + onFloor, 2000)
        XCTAssertEqual(Float(caught) / 2000, 0.2, accuracy: 0.025)
        XCTAssertEqual(Float(onFloor) / 2000, 0.8, accuracy: 0.025)
    }

    func testZeroAndFullCatchUseTheActualParticleAdvancePath() {
        for fraction: Float in [0, 1] {
            let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0))
            simulation.updateSurfaces([wire(fraction: fraction), floor])
            simulation.clear()
            var particle = SnowParticle(position: SIMD2(400, 140), velocity: SIMD2(0, 1000),
                                        radius: 1, opacity: 1, phase: 0, remainingLife: 1)
            XCTAssertTrue(simulation.advanceParticle(&particle, dt: 0.5, recycleOnContact: true))
            XCTAssertEqual(simulation.drifts[0].heights.contains(where: { $0 > 0 }), fraction == 1)
            XCTAssertEqual(simulation.drifts[1].heights.contains(where: { $0 > 0 }), fraction == 0)
        }
    }

    func testEachStringHasAnIndependentChanceToCatchPassingSnow() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0), seed: 8)
        simulation.updateSurfaces([wire(id: 1, y: 100), wire(id: 2, y: 200), floor])
        var hits = [0, 0, 0]
        for _ in 0..<2000 {
            simulation.clear()
            var particle = SnowParticle(position: SIMD2(400, 50), velocity: SIMD2(0, 1000),
                                        radius: 1, opacity: 1, phase: 0, remainingLife: 1)
            XCTAssertTrue(simulation.advanceParticle(&particle, dt: 0.6, recycleOnContact: true))
            for index in hits.indices where simulation.drifts[index].heights.contains(where: { $0 > 0 }) { hits[index] += 1 }
        }
        XCTAssertEqual(hits.reduce(0, +), 2000)
        XCTAssertEqual(Float(hits[0]) / 2000, 0.2, accuracy: 0.03)
        XCTAssertEqual(Float(hits[1]) / 2000, 0.16, accuracy: 0.03)
        XCTAssertEqual(Float(hits[2]) / 2000, 0.64, accuracy: 0.03)
    }

    func testAmbientWireDustingAndAccumulationRespectTheCatchFraction() {
        let full = SnowDrift(surface: wire(fraction: 1), cellCount: 101)
        let partial = SnowDrift(surface: wire(), cellCount: 101)
        let none = SnowDrift(surface: wire(fraction: 0), cellCount: 101)
        let fullDusting = full.heights.reduce(0, +)
        XCTAssertEqual(partial.heights.reduce(0, +), fullDusting * 0.2, accuracy: 0.001)
        for drift in [full, partial, none] {
            drift.clear()
            drift.accumulate(dt: 1, intensity: 1)
        }
        XCTAssertEqual(partial.heights.reduce(0, +), full.heights.reduce(0, +) * 0.2, accuracy: 0.001)
        XCTAssertEqual(none.heights.reduce(0, +), 0)
    }

    func testChangingThePercentagePreservesExistingSnowAndChangesFutureAccumulation() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0))
        simulation.updateScene(surfaces: [wire(fraction: 1)], bodies: [])
        simulation.step(dt: 1 / 30, cursor: nil)
        let before = simulation.drifts[0].heights
        simulation.updateScene(surfaces: [wire(fraction: 0)], bodies: [])
        for _ in 0..<120 { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertEqual(simulation.drifts[0].heights.reduce(0, +), before.reduce(0, +), accuracy: 0.001)
    }

    func testPushedSnowStillLandsAndInvalidPercentagesAreRejected() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0))
        simulation.updateSurfaces([wire(fraction: 0)])
        simulation.clear()
        let result = simulation.landGranularSnow(from: SIMD2(400, 140), to: SIMD2(400, 160), mass: 10)
        XCTAssertTrue(result.blocked)
        XCTAssertEqual(result.remaining, 0, accuracy: 0.001)
        XCTAssertEqual(simulation.drifts[0].heights.reduce(0, +) * simulation.drifts[0].spacing, 10, accuracy: 0.001)
        var invalid = wire()
        invalid.snowCatchFraction = .nan
        simulation.updateSurfaces([invalid])
        XCTAssertTrue(simulation.drifts.isEmpty)
        XCTAssertNil(WireSnowSupport.build(id: 1, points: [SIMD2(0, 100), SIMD2(800, 100)],
                                           size: SIMD2(800, 600), occluders: [], catchFraction: 1.1))
    }
}
