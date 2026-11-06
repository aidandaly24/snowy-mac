import XCTest
@testable import SnowCore

final class WinterVillageTests: XCTestCase {
    func testBlizzardEntersFromTheUpwindSideAcrossTheWholeScreenHeight() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), seed: 24)
        simulation.snowfall = .blizzard
        simulation.wind = DesktopVibe.blizzard.wind
        var bins = Array(repeating: 0, count: 10)
        for _ in 0..<2000 {
            let flake = simulation.newFlake(scattered: false)
            if flake.position.x < 0 {
                bins[min(9, max(0, Int(flake.position.y / 60)))] += 1
            }
        }
        XCTAssertGreaterThan(bins.reduce(0, +), 800)
        XCTAssertTrue(bins.allSatisfy { $0 > 40 })
        simulation.wind = WindSettings(vector: SIMD2(-1, 0))
        let rightEntries = (0..<300).filter { _ in simulation.newFlake(scattered: false).position.x > 800 }.count
        XCTAssertGreaterThan(rightEntries, 100)
    }

    private func windySimulation(debris: Int = 96) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0, debris: debris))
        simulation.snowfall = .blizzard
        simulation.wind = DesktopVibe.blizzard.wind
        simulation.updateSurfaces([Surface(id: 1, x: 100, y: 200, width: 400)])
        for i in simulation.drifts[0].heights.indices { simulation.drifts[0].heights[i] = 8 }
        return simulation
    }

    func testWindErosionConservesSnowArea() {
        let simulation = windySimulation()
        let drift = simulation.drifts[0]
        let before = drift.heights.reduce(0, +) * drift.spacing
        simulation.erodeSnowInWind(dt: 0.2, gust: 2)
        let remaining = drift.heights.reduce(0, +) * drift.spacing
        XCTAssertLessThan(remaining, before)
        XCTAssertGreaterThan(simulation.looseSnow.totalMass, 0)
        XCTAssertEqual(remaining + simulation.looseSnow.totalMass, before, accuracy: 0.05)
    }

    func testFullGranularStorageLeavesTheErodedSnowOnItsSupport() {
        let simulation = windySimulation(debris: 0)
        let before = simulation.drifts[0].heights
        simulation.erodeSnowInWind(dt: 0.2, gust: 2)
        XCTAssertEqual(simulation.drifts[0].heights, before)
        XCTAssertEqual(simulation.looseSnow.totalMass, 0)
    }

    func testCalmAndBatteryModeDoNotErodeExistingSnow() {
        let simulation = windySimulation()
        let before = simulation.drifts[0].heights
        simulation.wind = WindSettings()
        simulation.erodeSnowInWind(dt: 0.2)
        XCTAssertEqual(simulation.drifts[0].heights, before)
        simulation.wind = DesktopVibe.blizzard.wind
        simulation.ambientSnowfallEnabled = false
        simulation.erodeSnowInWind(dt: 0.2)
        XCTAssertEqual(simulation.drifts[0].heights, before)
    }

    func testFriendsGreetThenContinueWalking() {
        var friend = WinterFriend(x: 100)
        _ = friend.advance(dt: 1 / 30, size: SIMD2(800, 600), cursor: nil, bodies: [], reducedMotion: false, neighbors: [WinterFriend(x: 140)])
        XCTAssertTrue(friend.greetingFriend)
        XCTAssertEqual(friend.x, 100)
        for _ in 0..<120 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(800, 600), cursor: nil, bodies: [], reducedMotion: false, neighbors: [WinterFriend(x: 140)])
        }
        XCTAssertFalse(friend.greetingFriend)
        XCTAssertLessThan(friend.x, 100)
    }

    func testFriendsVisitVillageLandmarksWithoutGettingStuck() {
        var friend = WinterFriend(x: 100)
        _ = friend.advance(dt: 1 / 30, size: SIMD2(800, 600), cursor: nil, bodies: [], reducedMotion: false, landmarkX: 105)
        XCTAssertTrue(friend.visitingVillage)
        for _ in 0..<120 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(800, 600), cursor: nil, bodies: [], reducedMotion: false, landmarkX: 105)
        }
        XCTAssertFalse(friend.visitingVillage)
        XCTAssertLessThan(friend.x, 100)
    }

    private func wire(occluders: [SolidBody] = []) -> Surface {
        WireSnowSupport.build(id: 123, points: [SIMD2(0, 100), SIMD2(400, 200), SIMD2(800, 100)],
                              size: SIMD2(800, 600), occluders: occluders, catchFraction: 1)!
    }

    func testWireSnowSupportFollowsTheCurveAndCatchesAFallingFlake() {
        let support = wire()
        XCTAssertEqual(support.baseY(at: 0), 100, accuracy: 0.1)
        XCTAssertEqual(support.baseY(at: 400), 200, accuracy: 3)
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0))
        simulation.updateSurfaces([support])
        simulation.clear()
        let flake = SnowParticle(position: SIMD2(400, 230), velocity: SIMD2(0, 100), radius: 1,
                                 opacity: 1, phase: 0, remainingLife: 1)
        XCTAssertTrue(simulation.land(from: SIMD2(400, 170), particle: flake))
        XCTAssertGreaterThan(simulation.drifts[0].height(at: 400), 0)
        simulation.drifts[0].accumulate(dt: 1000, intensity: 10)
        XCTAssertLessThanOrEqual(simulation.drifts[0].heights.max()!, 3)
    }

    func testWindowsCoverAndShelterTheirPortionOfAHangingWire() {
        let support = wire(occluders: [SolidBody(id: 1, bounds: CGRect(x: 300, y: 150, width: 200, height: 100))])
        XCTAssertFalse(support.isExposed(at: 400))
        XCTAssertFalse(support.isSnowExposed(at: 400))
        XCTAssertTrue(support.isExposed(at: 100))
    }

    func testRemovingAWireReleasesItsSnowInsteadOfDeletingIt() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0))
        simulation.updateSurfaces([wire()])
        for i in simulation.drifts[0].heights.indices { simulation.drifts[0].heights[i] = 2 }
        let mass = simulation.drifts[0].heights.reduce(0, +) * simulation.drifts[0].spacing
        simulation.updateSurfaces([])
        XCTAssertTrue(simulation.drifts.isEmpty)
        XCTAssertEqual(simulation.looseSnow.totalMass + simulation.pendingTransferMass, mass, accuracy: 0.1)
    }

    func testMalformedWireProfilesCannotAllocateSnowState() {
        XCTAssertNil(WireSnowSupport.build(id: 1, points: [SIMD2(5, 10), SIMD2(5, 200)], size: SIMD2(800, 600), occluders: []))
        let simulation = SnowSimulation(size: SIMD2(800, 600))
        simulation.updateSurfaces([Surface(id: 1, x: 0, y: 100, width: 200, supportOffsets: [0, .infinity])])
        XCTAssertTrue(simulation.drifts.isEmpty)
    }
}
