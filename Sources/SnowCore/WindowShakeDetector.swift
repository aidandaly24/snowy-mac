import Foundation

public struct WindowShakeDetector: Sendable {
    private struct Motion: Sendable {
        var body: SolidBody
        var direction: Float = 0
        var reversals = 0
        var lastTurn: TimeInterval = -.infinity
        var lastShake: TimeInterval = -.infinity
    }
    private var motions: [UInt64: Motion] = [:]
    public init() {}

    public mutating func update(bodies: [SolidBody], now: TimeInterval, dragging: Bool) -> [UInt64] {
        guard dragging, now.isFinite else { motions.removeAll(keepingCapacity: true); return [] }
        let bodies = Array(bodies.prefix(64).filter { BodyChanges.valid($0) })
        let ids = Set(bodies.map(\.id))
        motions = motions.filter { ids.contains($0.key) }
        var shaken: [UInt64] = []
        for body in bodies {
            guard var motion = motions[body.id] else { motions[body.id] = Motion(body: body); continue }
            let dx = Float(body.bounds.midX - motion.body.bounds.midX)
            let dy = Float(body.bounds.midY - motion.body.bounds.midY)
            let sameSize = abs(body.bounds.width - motion.body.bounds.width) < 2 && abs(body.bounds.height - motion.body.bounds.height) < 2
            motion.body = body
            if abs(dx) >= 14, abs(dy) < abs(dx) * 1.4, sameSize {
                let direction: Float = dx > 0 ? 1 : -1
                if now - motion.lastTurn > 0.85 { motion.reversals = 0; motion.direction = 0 }
                if motion.direction != 0, direction != motion.direction { motion.reversals += 1 }
                motion.direction = direction
                motion.lastTurn = now
                if motion.reversals >= 3, now - motion.lastShake > 1.2 {
                    shaken.append(body.id)
                    motion.reversals = 0
                    motion.lastShake = now
                }
            }
            motions[body.id] = motion
        }
        return shaken
    }
}
