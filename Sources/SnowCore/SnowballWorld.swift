import Foundation

public struct PlaySnowball: Sendable {
    public let id: UInt64
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    var age: Float = 0
}

public struct SnowballImpact: Sendable {
    public let position: SIMD2<Float>
    public let mass: Float
}

public struct SnowballWorld: Sendable {
    public static let maximumBalls = 8
    public private(set) var balls: [PlaySnowball] = []
    private var nextID: UInt64 = 0

    public init() {}
    public mutating func clear() { balls.removeAll(keepingCapacity: true) }

    @discardableResult
    public mutating func launch(from position: SIMD2<Float>, velocity: SIMD2<Float>) -> Bool {
        guard balls.count < Self.maximumBalls, position.x.isFinite, position.y.isFinite,
              velocity.x.isFinite, velocity.y.isFinite, abs(position.x) < 100_000, abs(position.y) < 100_000 else { return false }
        let speed = hypot(Double(velocity.x), Double(velocity.y))
        let safe = speed > 900 ? velocity * Float(900 / speed) : velocity
        nextID &+= 1
        balls.append(PlaySnowball(id: nextID, position: position, velocity: safe))
        return true
    }

    public mutating func step(dt: Float, size: SIMD2<Float>, bodies: [SolidBody], wind: SIMD2<Float>) -> [SnowballImpact] {
        guard dt.isFinite, dt > 0, size.x.isFinite, size.y.isFinite, size.x > 16, size.y > 16 else { return [] }
        let dt = min(0.05, dt)
        var remaining: [PlaySnowball] = []
        var impacts: [SnowballImpact] = []
        for var ball in balls {
            ball.age += dt
            ball.velocity.y += 380 * dt
            if wind.x.isFinite { ball.velocity.x += max(-80, min(80, wind.x)) * 0.04 * dt }
            let end = ball.position + ball.velocity * dt
            var first: ParticleHit?
            for body in bodies.prefix(64) where BodyChanges.valid(body) {
                if let hit = ParticleCollision.hit(from: ball.position, to: end, radius: 6,
                                                   rectangle: body.bounds, cornerRadius: body.cornerRadius),
                   first == nil || hit.time < first!.time { first = hit }
            }
            if end.y >= size.y - 6, ball.velocity.y > 0 {
                let t = max(0, min(1, (size.y - 6 - ball.position.y) / max(0.001, end.y - ball.position.y)))
                if first == nil || t < first!.time {
                    first = ParticleHit(time: t, position: ball.position + (end - ball.position) * t, normal: SIMD2(0, -1))
                }
            }
            if let first {
                impacts.append(SnowballImpact(position: first.position + first.normal, mass: 65))
            } else if ball.age < 6, end.x > -40, end.x < size.x + 40, end.y < size.y + 20 {
                ball.position = end
                remaining.append(ball)
            }
        }
        balls = remaining
        return impacts
    }
}
