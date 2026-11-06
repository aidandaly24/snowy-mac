import AppKit
import SnowCore

@MainActor
final class WindGustView {
    let view: NSView
    private let size: CGSize
    private var streaks: [CAShapeLayer] = []
    private var phase: Double = 0
    private var previousTime: TimeInterval?

    init(size: CGSize) {
        self.size = size
        view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        for index in 0..<8 {
            let streak = CAShapeLayer()
            streak.strokeColor = NSColor(calibratedRed: 0.85, green: 0.95, blue: 1, alpha: 1).cgColor
            streak.fillColor = nil
            streak.lineWidth = index.isMultiple(of: 3) ? 1.3 : 0.7
            streak.lineCap = .round
            streak.isHidden = true
            view.layer?.addSublayer(streak)
            streaks.append(streak)
        }
    }

    func resetInteraction() { previousTime = nil }

    func advance(now: TimeInterval, wind: WindSettings, snowfall: Snowfall, quiet: Bool) {
        let dt = min(0.05, max(0, previousTime.map { now - $0 } ?? 0))
        previousTime = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard !quiet, snowfall == .blizzard, wind.speedFraction > 0.2 else {
            for streak in streaks { streak.isHidden = true }
            return
        }
        phase += dt * (0.08 + Double(wind.speedFraction) * 0.16)
        let diagonal = hypot(size.width, size.height)
        let vector = CGVector(dx: CGFloat(wind.vector.x / wind.speedFraction), dy: CGFloat(wind.vector.y / wind.speedFraction))
        for (index, streak) in streaks.enumerated() {
            let progress = (phase + Double(index) * 0.173).truncatingRemainder(dividingBy: 1)
            let travel = (CGFloat(progress) - 0.5) * diagonal * 1.5
            let across = (CGFloat((index * 37) % 101) / 100 - 0.5) * diagonal * 0.9
            let start = CGPoint(x: size.width / 2 + vector.dx * travel - vector.dy * across,
                                y: size.height / 2 + vector.dy * travel + vector.dx * across)
            let length = CGFloat(150 + (index % 3) * 65)
            let end = CGPoint(x: start.x + vector.dx * length, y: start.y + vector.dy * length)
            let bend = CGFloat(sin(phase * 5 + Double(index))) * 8
            let path = CGMutablePath()
            path.move(to: CGPoint(x: start.x, y: size.height - start.y))
            path.addQuadCurve(to: CGPoint(x: end.x, y: size.height - end.y),
                              control: CGPoint(x: (start.x + end.x) / 2 - vector.dy * bend,
                                               y: size.height - (start.y + end.y) / 2 - vector.dx * bend))
            let bounds = path.boundingBoxOfPath.insetBy(dx: -3, dy: -3)
            var offset = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            streak.frame = bounds
            streak.path = path.copy(using: &offset)
            streak.opacity = Float(sin(progress * .pi)) * 0.23 * wind.speedFraction
            streak.isHidden = false
        }
    }
}
