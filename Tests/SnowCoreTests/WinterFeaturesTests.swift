import XCTest
@testable import SnowCore

final class WinterFeaturesTests: XCTestCase {
    func testBatteryPolicyRemovesAmbientAnimationAndKeepsThermalProtection() {
        let quiet = RenderPolicy(lowPower: false, thermalLevel: 0, reducedMotion: false, batteryFriendly: true)
        XCTAssertEqual(quiet.framesPerSecond, 10)
        XCTAssertEqual(quiet.particleScale, 0)
        XCTAssertLessThanOrEqual(quiet.renderScale, 0.75)
        XCTAssertFalse(quiet.suspended)
        XCTAssertTrue(RenderPolicy(lowPower: false, thermalLevel: 3, reducedMotion: false, batteryFriendly: true).suspended)
        XCTAssertEqual(RenderPolicy(lowPower: false, thermalLevel: 0, reducedMotion: false).framesPerSecond, 30)
    }

    func testStaticBatterySceneDoesNotRegrowSnowOrRebuildAnUnchangedMesh() {
        let simulation = SnowSimulation(size: SIMD2(800, 600))
        simulation.updateSurfaces([Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 600, width: 800)])
        simulation.ambientSnowfallEnabled = false
        simulation.particleScale = 0
        let heights = simulation.drifts[0].heights
        let revision = simulation.meshRevision
        for _ in 0..<120 { simulation.step(dt: 0.1, cursor: nil) }
        XCTAssertEqual(simulation.drifts[0].heights, heights)
        XCTAssertEqual(simulation.meshRevision, revision)
        XCTAssertTrue(simulation.flakes.isEmpty)
    }

    func testBatteryModeStillRespondsToSweepingExistingSnow() {
        let simulation = SnowSimulation(size: SIMD2(800, 600))
        simulation.updateSurfaces([Surface(id: 1, x: 100, y: 200, width: 400)])
        for i in simulation.drifts[0].heights.indices { simulation.drifts[0].heights[i] = 8 }
        simulation.ambientSnowfallEnabled = false
        simulation.particleScale = 0
        simulation.step(dt: 0.1, cursor: SIMD2(100, 195))
        simulation.step(dt: 0.1, cursor: SIMD2(500, 195))
        XCTAssertGreaterThan(simulation.looseSnow.totalMass, 0)
        XCTAssertLessThan(simulation.drifts[0].height(at: 200), 8)
    }

    func testSnowballsHaveBoundedStorageAndRejectMalformedInput() {
        var world = SnowballWorld()
        XCTAssertFalse(world.launch(from: SIMD2(.nan, 0), velocity: .zero))
        for _ in 0..<8 { XCTAssertTrue(world.launch(from: SIMD2(50, 100), velocity: SIMD2(20, -100))) }
        XCTAssertFalse(world.launch(from: SIMD2(50, 100), velocity: .zero))
        XCTAssertEqual(world.balls.count, SnowballWorld.maximumBalls)
    }

    func testSnowballCannotTunnelThroughAThinWindow() {
        var world = SnowballWorld()
        world.launch(from: SIMD2(100, 100), velocity: SIMD2(900, 0))
        let wall = SolidBody(id: 1, bounds: CGRect(x: 140, y: 0, width: 5, height: 300))
        let impacts = world.step(dt: 0.05, size: SIMD2(500, 400), bodies: [wall], wind: .zero)
        XCTAssertEqual(impacts.count, 1)
        XCTAssertLessThan(impacts[0].position.x, 140)
        XCTAssertTrue(world.balls.isEmpty)
    }

    func testSnowballFallsAndSplashesOnTheFloor() {
        var world = SnowballWorld()
        world.launch(from: SIMD2(200, 100), velocity: SIMD2(0, -100))
        var impacts: [SnowballImpact] = []
        for _ in 0..<180 { impacts += world.step(dt: 1 / 30, size: SIMD2(500, 400), bodies: [], wind: .zero) }
        XCTAssertEqual(impacts.count, 1)
        XCTAssertGreaterThan(impacts[0].position.y, 380)
        XCTAssertLessThan(impacts[0].position.y, 400)
        XCTAssertTrue(world.balls.isEmpty)
    }

    func testShakingRequiresRapidDirectionChangesWhileDragging() {
        var detector = WindowShakeDetector()
        var shaken: [UInt64] = []
        for (index, x) in [0, 50, -10, 60, -15].enumerated() {
            shaken += detector.update(bodies: [SolidBody(id: 1, bounds: CGRect(x: x, y: 50, width: 300, height: 200))],
                                      now: Double(index) * 0.1, dragging: true)
        }
        XCTAssertEqual(shaken, [1])
        for (index, x) in [0, 50, -10, 60, -15].enumerated() {
            XCTAssertTrue(detector.update(bodies: [SolidBody(id: 1, bounds: CGRect(x: x, y: 50, width: 300, height: 200))],
                                          now: 2 + Double(index) * 0.1, dragging: false).isEmpty)
        }
    }

    func testNormalSlowWindowMovesDoNotCountAsShakes() {
        var detector = WindowShakeDetector()
        for (index, x) in [0, 50, -10, 60, -15].enumerated() {
            XCTAssertTrue(detector.update(bodies: [SolidBody(id: 1, bounds: CGRect(x: x, y: 50, width: 300, height: 200))],
                                          now: Double(index), dragging: true).isEmpty)
        }
    }

    func testShakingMovesSnowIntoTheExistingBoundedMaterialField() {
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: SimulationBudget(flakes: 0))
        simulation.updateSurfaces([Surface(id: 1, x: 200, y: 150, width: 300)])
        let drift = simulation.drifts[0]
        for i in drift.heights.indices { drift.heights[i] = 5 }
        let before = drift.heights.reduce(0, +) * drift.spacing
        simulation.shakeSnow(fromSurfaceID: 1)
        let onCap = drift.heights.reduce(0, +) * drift.spacing
        XCTAssertLessThan(onCap, before)
        XCTAssertEqual(onCap + simulation.looseSnow.totalMass, before, accuracy: 0.05)
        XCTAssertLessThanOrEqual(simulation.looseSnow.active.count, simulation.budget.maximumGranules)
    }

    func testVibesHaveDistinctWeatherWithinExistingWindLimits() {
        XCTAssertGreaterThan(DesktopVibe.blizzard.snowfall.density, Snowfall.flurry.density)
        XCTAssertLessThan(DesktopVibe.cozyVillage.snowfall.density, Snowfall.steady.density)
        XCTAssertGreaterThan(DesktopVibe.blizzard.wind.velocity.x, 60)
        XCTAssertLessThanOrEqual(DesktopVibe.blizzard.wind.speedFraction, 1)
    }

    func testBlizzardKeepsTheExistingParticleAndMeshBudgets() {
        let budget = SimulationBudget(flakes: 80, debris: 8, cells: 160, surfaces: 8)
        let simulation = SnowSimulation(size: SIMD2(800, 600), budget: budget)
        simulation.snowfall = DesktopVibe.blizzard.snowfall
        simulation.wind = DesktopVibe.blizzard.wind
        simulation.updateSurfaces([Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 600, width: 800)])
        for _ in 0..<120 { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertEqual(simulation.flakes.count, 80)
        XCTAssertLessThanOrEqual(simulation.mesh.count, budget.maximumSnowVertices)
        XCTAssertTrue(simulation.flakes.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    func testFriendWalksAndLeavesFootprintsInsideTheDesktop() {
        var friend = WinterFriend(x: 80)
        var tracks = 0
        for _ in 0..<300 {
            if let mark = friend.advance(dt: 1 / 30, size: SIMD2(300, 200), cursor: nil, bodies: [], reducedMotion: false) {
                tracks += 1
                XCTAssertGreaterThanOrEqual(mark.x, 20)
                XCTAssertLessThanOrEqual(mark.x, 280)
            }
        }
        XCTAssertGreaterThan(tracks, 5)
        XCTAssertNotEqual(friend.x, 80)
    }

    func testFriendStopsAndLooksAtNearbyCursor() {
        var friend = WinterFriend(x: 80)
        let track = friend.advance(dt: 1 / 30, size: SIMD2(300, 200), cursor: SIMD2(50, 170), bodies: [], reducedMotion: false)
        XCTAssertTrue(friend.watchingCursor)
        XCTAssertEqual(friend.direction, -1)
        XCTAssertEqual(friend.x, 80)
        XCTAssertNil(track)
    }

    func testFriendTurnsBeforeAnObstacleAndHonorsReducedMotion() {
        var friend = WinterFriend(x: 80)
        let body = SolidBody(id: 1, bounds: CGRect(x: 100, y: 150, width: 60, height: 50))
        for _ in 0..<100 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(300, 200), cursor: nil, bodies: [body], reducedMotion: false)
            XCTAssertFalse(CGRect(x: CGFloat(friend.x - 14), y: 157, width: 28, height: 40).intersects(body.bounds))
        }
        let position = friend.x
        for _ in 0..<100 { _ = friend.advance(dt: 1 / 30, size: SIMD2(300, 200), cursor: nil, bodies: [], reducedMotion: true) }
        XCTAssertEqual(friend.x, position)
    }
}
