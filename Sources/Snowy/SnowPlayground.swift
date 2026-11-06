import AppKit
import SnowCore

/// Click-through play: Option gestures are observed without intercepting clicks.
@MainActor
final class SnowPlayground {
    let view: NSView
    var onImpact: ((SIMD2<Float>, Float) -> Void)?
    var onBuildSnowman: ((Double) -> Void)?
    private let size: CGSize
    private var world = SnowballWorld()
    private var layers: [UInt64: CALayer] = [:]
    private let guide = CAShapeLayer()
    private let preview = CALayer()
    private let reveal = CALayer()
    private var previousTime: TimeInterval?
    private var gestureStart: SIMD2<Float>?
    private var gestureTool: SnowTool?
    private var holdTime: TimeInterval = 0
    private var wasOptionDown = false

    init(size: CGSize) {
        self.size = size
        view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.autoresizingMask = [.width, .height]
        guide.strokeColor = NSColor.white.withAlphaComponent(0.7).cgColor
        guide.fillColor = nil
        guide.lineWidth = 1.5
        guide.lineDashPattern = [3, 4]
        view.layer?.addSublayer(guide)
        preview.contents = DecorationCatalog.piece("Snowman")?.image
        preview.magnificationFilter = .nearest
        preview.bounds = CGRect(x: 0, y: 0, width: 64, height: 90)
        reveal.backgroundColor = NSColor.white.cgColor
        preview.mask = reveal
        preview.isHidden = true
        view.layer?.addSublayer(preview)
    }

    func resetInteraction() {
        previousTime = nil
        gestureStart = nil
        gestureTool = nil
        holdTime = 0
        wasOptionDown = false
        preview.isHidden = true
        guide.path = nil
    }

    func clear() {
        world.clear()
        for layer in layers.values { layer.removeFromSuperlayer() }
        layers.removeAll()
        resetInteraction()
    }

    func advance(now: TimeInterval, cursor: SIMD2<Float>?, canStart: Bool, optionDown: Bool,
                 tool: SnowTool, bodies: [SolidBody], wind: WindSettings, dock: CGRect?) {
        let dt = min(0.05, max(0, previousTime.map { now - $0 } ?? 0))
        previousTime = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if optionDown, !wasOptionDown, canStart, let cursor, tool == .snowball || tool == .snowman {
            gestureStart = SIMD2(max(10, min(Float(size.width) - 10, cursor.x)),
                                 max(10, min(Float(size.height) - 12, cursor.y)))
            gestureTool = tool
            holdTime = 0
        }
        if optionDown, let start = gestureStart {
            holdTime += dt
            if gestureTool == .snowball, let cursor {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: CGFloat(start.x), y: size.height - CGFloat(start.y)))
                path.addLine(to: CGPoint(x: CGFloat(cursor.x), y: size.height - CGFloat(cursor.y)))
                let bounds = path.boundingBoxOfPath.insetBy(dx: -3, dy: -3)
                var offset = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
                guide.frame = bounds
                guide.path = path.copy(using: &offset)
            } else if gestureTool == .snowman {
                preview.isHidden = false
                let onDock = dock.map { CGFloat(start.x) >= $0.minX && CGFloat(start.x) <= $0.maxX } ?? false
                let base = onDock ? size.height - (dock?.minY ?? size.height) : 0
                preview.position = CGPoint(x: CGFloat(start.x), y: base + 45)
                reveal.frame = CGRect(x: 0, y: 0, width: 64, height: 90 * min(1, holdTime / 1.2))
            }
        }
        if !optionDown, wasOptionDown, let start = gestureStart {
            if gestureTool == .snowball {
                var velocity = ((cursor ?? start) - start) * 3.5
                if hypot(velocity.x, velocity.y) < 30 { velocity = SIMD2(180, -260) }
                world.launch(from: start, velocity: velocity)
            } else if gestureTool == .snowman, holdTime >= 1.2 {
                onBuildSnowman?(Double(start.x) / max(1, Double(size.width)))
            }
            gestureStart = nil
            gestureTool = nil
            preview.isHidden = true
            guide.path = nil
        }
        wasOptionDown = optionDown
        for impact in world.step(dt: Float(dt), size: SIMD2(Float(size.width), Float(size.height)), bodies: bodies, wind: wind.velocity) {
            onImpact?(impact.position, impact.mass)
        }
        let ids = Set(world.balls.map(\.id))
        for (id, layer) in layers where !ids.contains(id) { layer.removeFromSuperlayer(); layers[id] = nil }
        for ball in world.balls {
            let layer: CALayer
            if let existing = layers[ball.id] { layer = existing }
            else {
                layer = CALayer()
                layer.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
                layer.cornerRadius = 6
                layer.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.99, blue: 1, alpha: 1).cgColor
                layer.borderColor = NSColor(calibratedRed: 0.63, green: 0.78, blue: 0.86, alpha: 0.8).cgColor
                layer.borderWidth = 1
                view.layer?.addSublayer(layer)
                layers[ball.id] = layer
            }
            layer.position = CGPoint(x: CGFloat(ball.position.x), y: size.height - CGFloat(ball.position.y))
        }
    }
}
