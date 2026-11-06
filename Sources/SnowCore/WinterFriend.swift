import Foundation

public enum WinterFriendKind: String, CaseIterable, Sendable {
    case mixed = "Village Mix"
    case penguin = "Penguin"
    case fox = "Fox"
    case snowman = "Snowman"
    case none = "None"

    public var bodySize: SIMD2<Float> { self == .fox ? SIMD2(49, 31) : SIMD2(31, 44) }
}

/// A ground-level walker, advanced by the existing snow frame clock.
public struct WinterFriend: Sendable {
    public private(set) var x: Float
    public private(set) var direction: Float = 1
    public private(set) var phase: Float = 0
    public private(set) var watchingCursor = false
    public private(set) var isWalking = false
    public private(set) var isVisible = true
    public let bodySize: SIMD2<Float>
    public var greetingFriend: Bool { pause == .greeting && pauseTime > 0 }
    public var visitingVillage: Bool { pause == .landmark && pauseTime > 0 }

    private enum Pause: Sendable { case none, greeting, landmark }
    private var pause = Pause.none
    private var pauseTime: Float = 0
    private var resumeDirection: Float = 1
    private var greetingCooldown: Float = 0
    private var distanceSinceStep: Float = 0
    private var leftFoot = false

    public init(x: Float, direction: Float = 1, kind: WinterFriendKind = .penguin) {
        self.x = x.isFinite ? x : 80
        self.direction = direction < 0 ? -1 : 1
        self.resumeDirection = self.direction
        self.bodySize = kind.bodySize
    }

    /// Used for initial placement too: a crowded lane never falls back to stacking sprites.
    @discardableResult
    public mutating func place(size: SIMD2<Float>, bodies: [SolidBody], neighbors: [WinterFriend] = []) -> Bool {
        locate(in: walkingSpans(size: size, bodies: bodies, neighbors: neighbors)) != nil
    }

    public mutating func advance(dt: Float, size: SIMD2<Float>, cursor: SIMD2<Float>?,
                                 bodies: [SolidBody], reducedMotion: Bool, neighbors: [WinterFriend] = [],
                                 landmarkX: Float? = nil) -> SIMD2<Float>? {
        isWalking = false
        watchingCursor = false
        guard dt.isFinite, dt > 0 else { return nil }
        guard let lane = locate(in: walkingSpans(size: size, bodies: bodies, neighbors: neighbors)) else { return nil }
        let dt = min(dt, 0.05)
        let validCursor = cursor.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        watchingCursor = validCursor.map { abs($0.x - x) < 105 && abs($0.y - (size.y - 25)) < 90 } ?? false
        if watchingCursor, let cursor = validCursor {
            // A pointer hovering around the sprite's center must not flicker its facing.
            if abs(cursor.x - x) > 8 { direction = cursor.x < x ? -1 : 1 }
            return nil
        }
        guard !reducedMotion else { return nil }
        greetingCooldown = max(0, greetingCooldown - dt)
        if pauseTime > 0 {
            pauseTime = max(0, pauseTime - dt)
            if pauseTime == 0 {
                direction = resumeDirection
                greetingCooldown = 6
                pause = .none
            }
            return nil
        }
        let nearest = neighbors.prefix(5).filter { $0.isVisible && $0.x.isFinite }
            .min { abs($0.x - x) < abs($1.x - x) }
        if let nearest, abs(nearest.x - x) < (bodySize.x + nearest.bodySize.x) / 2 + 22,
           greetingCooldown == 0 {
            direction = nearest.x < x ? -1 : 1
            resumeDirection = -direction
            pause = .greeting
            pauseTime = 2.2
            return nil
        }
        if let landmarkX, landmarkX.isFinite, abs(landmarkX - x) < 12, greetingCooldown == 0 {
            pause = .landmark
            pauseTime = 1.8
            resumeDirection = -direction
            return nil
        }

        // Stay still in a tiny pocket. Turning every frame would look like shaking.
        guard lane.upper - lane.lower >= 12 else { return nil }
        let step = 16 * dt
        let forwardSpace = direction > 0 ? lane.upper - x : x - lane.lower
        if forwardSpace < 0.001 { direction *= -1 }
        let next = max(lane.lower, min(lane.upper, x + direction * step))
        let distance = abs(next - x)
        guard distance > 0.001 else { return nil }
        isWalking = true
        phase = (phase + dt * 5).truncatingRemainder(dividingBy: .pi * 2)
        distanceSinceStep += distance
        x = next
        guard distanceSinceStep >= 12 else { return nil }
        distanceSinceStep.formTruncatingRemainder(dividingBy: 12)
        leftFoot.toggle()
        return SIMD2(x, size.y - (leftFoot ? 3 : 7))
    }

    private func walkingSpans(size: SIMD2<Float>, bodies: [SolidBody], neighbors: [WinterFriend]) -> [Span] {
        guard size.x.isFinite, size.y.isFinite, size.x > 48, size.y > 48 else { return [] }
        let radius = bodySize.x / 2
        var spans = [Span(radius + 4, size.x - radius - 4)]
        let top = size.y - bodySize.y - 4
        for body in bodies.prefix(64) {
            let bounds = body.bounds
            guard bounds.minX.isFinite, bounds.maxX.isFinite, bounds.minY.isFinite, bounds.maxY.isFinite,
                  bounds.maxY > CGFloat(top), bounds.minY < CGFloat(size.y - 2) else { continue }
            spans = Geometry.subtract(Span(Float(bounds.minX) - radius - 3,
                                           Float(bounds.maxX) + radius + 3), from: spans)
        }
        for neighbor in neighbors.prefix(5) where neighbor.isVisible && neighbor.x.isFinite {
            let clearance = radius + neighbor.bodySize.x / 2 + 6
            spans = Geometry.subtract(Span(neighbor.x - clearance, neighbor.x + clearance), from: spans)
        }
        return spans.filter { $0.upper - $0.lower > 0.01 }
    }

    private mutating func locate(in spans: [Span]) -> Span? {
        guard let lane = spans.min(by: {
            abs(max($0.lower, min($0.upper, x)) - x) < abs(max($1.lower, min($1.upper, x)) - x)
        }) else {
            isVisible = false
            isWalking = false
            watchingCursor = false
            pauseTime = 0
            pause = .none
            return nil
        }
        isVisible = true
        if !lane.contains(x) {
            // A window can move over a resident between frames. Recover to free ground once,
            // rather than repeatedly reversing inside the same obstruction.
            x = max(lane.lower, min(lane.upper, x))
            direction = x <= lane.lower ? 1 : -1
            pauseTime = 0
            pause = .none
            greetingCooldown = max(greetingCooldown, 0.6)
            distanceSinceStep = 0
        }
        return lane
    }
}
