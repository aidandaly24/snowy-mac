import XCTest
@testable import SnowCore

final class WinterFriendMovementTests: XCTestCase {
    func testWindowMovingOverAFriendDoesNotCauseRapidDirectionFlips() {
        var friend = WinterFriend(x: 110)
        let window = SolidBody(id: 1, bounds: CGRect(x: 80, y: 140, width: 65, height: 60))
        var flips = 0
        var lastDirection = friend.direction
        for _ in 0..<240 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(300, 200), cursor: nil,
                               bodies: [window], reducedMotion: false)
            if friend.direction != lastDirection { flips += 1 }
            lastDirection = friend.direction
        }
        XCTAssertLessThan(flips, 5, "A blocked walker must not alternate direction every frame.")
        XCTAssertFalse(CGRect(x: CGFloat(friend.x - 14), y: 157, width: 28, height: 40).intersects(window.bounds))
    }

    func testTinyCursorMovementDoesNotFlipFacingEveryFrame() {
        var friend = WinterFriend(x: 100)
        var flips = 0
        var lastDirection = friend.direction
        for index in 0..<90 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(400, 200),
                               cursor: SIMD2(100 + (index.isMultiple(of: 2) ? -1 : 1), 175),
                               bodies: [], reducedMotion: false)
            if friend.direction != lastDirection { flips += 1 }
            lastDirection = friend.direction
        }
        XCTAssertLessThanOrEqual(flips, 1)
    }

    func testFiveMixedFriendsKeepSpriteSizedClearanceWhileWindowsMove() {
        let kinds: [WinterFriendKind] = [.penguin, .fox, .snowman, .fox, .penguin]
        var friends: [WinterFriend] = []
        let size = SIMD2<Float>(800, 200)
        for (index, kind) in kinds.enumerated() {
            var friend = WinterFriend(x: 100 + Float(index) * 35, direction: index.isMultiple(of: 2) ? 1 : -1, kind: kind)
            friend.place(size: size, bodies: [], neighbors: friends)
            friends.append(friend)
        }
        var greeted = false
        for frame in 0..<1800 {
            let bodies = frame >= 300 && frame < 1200
                ? [SolidBody(id: 1, bounds: CGRect(x: 250 + Double(frame / 300) * 25, y: 110, width: 240, height: 90))] : []
            for index in friends.indices {
                let neighbors = friends.enumerated().filter { $0.offset != index }.map(\.element)
                _ = friends[index].advance(dt: 1 / 30, size: size, cursor: nil,
                                           bodies: bodies, reducedMotion: false, neighbors: neighbors)
                greeted = greeted || friends[index].greetingFriend
            }
            for first in friends.indices where friends[first].isVisible {
                for second in friends.indices where second > first && friends[second].isVisible {
                    let clearance = (friends[first].bodySize.x + friends[second].bodySize.x) / 2 + 6
                    XCTAssertGreaterThanOrEqual(abs(friends[first].x - friends[second].x), clearance - 0.01)
                }
                let friend = friends[first]
                let bounds = CGRect(x: CGFloat(friend.x - friend.bodySize.x / 2),
                                    y: CGFloat(size.y - friend.bodySize.y - 2),
                                    width: CGFloat(friend.bodySize.x), height: CGFloat(friend.bodySize.y))
                XCTAssertFalse(bodies.contains { $0.bounds.intersects(bounds) })
            }
        }
        XCTAssertTrue(greeted)
    }

    func testCrowdedPlacementWaitsForSpaceInsteadOfStackingFriends() {
        let size = SIMD2<Float>(90, 200)
        var first = WinterFriend(x: 45, kind: .fox)
        first.place(size: size, bodies: [])
        var second = WinterFriend(x: 45, kind: .fox)
        XCTAssertFalse(second.place(size: size, bodies: [], neighbors: [first]))
        XCTAssertFalse(second.isVisible)
        _ = second.advance(dt: 1 / 30, size: SIMD2(400, 200), cursor: nil,
                           bodies: [], reducedMotion: false, neighbors: [first])
        XCTAssertTrue(second.isVisible)
        XCTAssertGreaterThanOrEqual(abs(second.x - first.x), 55 - 0.01)
    }

    func testACompletelyBlockedFloorCanRecoverWhenTheWindowMovesAway() {
        var friend = WinterFriend(x: 100)
        let window = SolidBody(id: 1, bounds: CGRect(x: 0, y: 100, width: 400, height: 100))
        for _ in 0..<120 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(400, 200), cursor: nil,
                               bodies: [window], reducedMotion: false)
            XCTAssertFalse(friend.isVisible)
            XCTAssertFalse(friend.isWalking)
        }
        let phase = friend.phase
        _ = friend.advance(dt: 1 / 30, size: SIMD2(400, 200), cursor: nil, bodies: [], reducedMotion: false)
        XCTAssertTrue(friend.isVisible)
        XCTAssertTrue(friend.isWalking)
        XCTAssertGreaterThan(friend.phase, phase)
    }

    func testNarrowWalkingPocketDoesNotAnimateOrReverseInPlace() {
        var friend = WinterFriend(x: 22)
        let wall = SolidBody(id: 1, bounds: CGRect(x: 44, y: 100, width: 356, height: 100))
        let direction = friend.direction
        for _ in 0..<120 {
            _ = friend.advance(dt: 1 / 30, size: SIMD2(400, 200), cursor: nil,
                               bodies: [wall], reducedMotion: false)
            XCTAssertTrue(friend.isVisible)
            XCTAssertFalse(friend.isWalking)
            XCTAssertEqual(friend.phase, 0)
            XCTAssertEqual(friend.direction, direction)
        }
    }

}
