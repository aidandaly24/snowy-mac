import AppKit
import SnowCore

@MainActor
final class WinterFriendView {
    let view: NSView
    var kind: WinterFriendKind = .mixed { didSet { if kind != oldValue { rebuildResidents() } } }
    var count = 3 {
        didSet {
            count = min(5, max(1, count))
            if count != oldValue { rebuildResidents() }
        }
    }
    var isEmpty: Bool { residents.isEmpty }
    private let size: CGSize
    private struct Resident {
        var state: WinterFriend
        var kind: WinterFriendKind
        let character: CALayer
        let bubble: CATextLayer
    }
    private var residents: [Resident] = []
    private var footprints: [(layer: CALayer, age: TimeInterval)] = []
    private var previousTime: TimeInterval?
    private var needsPlacement = true

    init(size: CGSize) {
        self.size = size
        view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.autoresizingMask = [.width, .height]
        rebuildResidents()
    }

    func resetInteraction() { previousTime = nil }
    func resetPositions() {
        needsPlacement = true
        previousTime = nil
        for footprint in footprints { footprint.layer.removeFromSuperlayer() }
        footprints.removeAll()
    }

    private func rebuildResidents() {
        let previous = residents
        let total = kind == .none ? 0 : count
        let mix: [WinterFriendKind] = [.penguin, .fox, .snowman]
        var next: [Resident] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for index in 0..<total {
            let type = kind == .mixed ? mix[index % mix.count] : kind
            let character = index < previous.count ? previous[index].character : CALayer()
            let bubble = index < previous.count ? previous[index].bubble : CATextLayer()
            let name = type == .fox ? "Winter fox" : (type == .snowman ? "Snowman" : "Winter penguin")
            character.contents = DecorationCatalog.piece(name)?.image
            character.magnificationFilter = .nearest
            character.minificationFilter = .nearest
            view.layer?.addSublayer(character)
            bubble.fontSize = 12
            bubble.alignmentMode = .center
            bubble.foregroundColor = NSColor.white.cgColor
            bubble.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 0.72).cgColor
            bubble.cornerRadius = 7
            bubble.bounds = CGRect(x: 0, y: 0, width: 21, height: 20)
            bubble.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            bubble.isHidden = true
            view.layer?.addSublayer(bubble)
            let state = index < previous.count ? previous[index].state : WinterFriend(x: Float(size.width * 0.36), direction: index.isMultiple(of: 2) ? 1 : -1, kind: type)
            next.append(Resident(state: state, kind: type, character: character, bubble: bubble))
        }
        if total < previous.count {
            for index in total..<previous.count {
                previous[index].character.removeFromSuperlayer()
                previous[index].bubble.removeFromSuperlayer()
            }
        }
        residents = next
        needsPlacement = true
    }

    private func placeResidents(avoiding bodies: [SolidBody]) {
        var placed: [WinterFriend] = []
        for index in residents.indices {
            let preferred = size.width * ([0.36, 0.40, 0.68, 0.73, 0.31][index])
            var state = WinterFriend(x: Float(preferred), direction: index.isMultiple(of: 2) ? 1 : -1,
                                     kind: residents[index].kind)
            state.place(size: SIMD2(Float(size.width), Float(size.height)), bodies: bodies, neighbors: placed)
            residents[index].state = state
            placed.append(state)
        }
        needsPlacement = false
    }

    func advance(now: TimeInterval, cursor: SIMD2<Float>?, bodies: [SolidBody], reducedMotion: Bool,
                 landmarks: [Float] = []) {
        let dt = min(0.05, max(0, previousTime.map { now - $0 } ?? 0))
        previousTime = now
        if needsPlacement { placeResidents(avoiding: bodies) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for index in footprints.indices { footprints[index].age += dt }
        for footprint in footprints { footprint.layer.opacity = Float(max(0, 1 - footprint.age / 18)) * 0.45 }
        while let first = footprints.first, first.age >= 18 { first.layer.removeFromSuperlayer(); footprints.removeFirst() }
        var states = residents.map(\.state)
        for index in residents.indices {
            let neighbors = states.enumerated().filter { $0.offset != index }.map(\.element)
            let landmark = landmarks.min { abs($0 - states[index].x) < abs($1 - states[index].x) }
            if let printAt = residents[index].state.advance(dt: Float(dt), size: SIMD2(Float(size.width), Float(size.height)),
                                                            cursor: cursor, bodies: bodies, reducedMotion: reducedMotion,
                                                            neighbors: neighbors, landmarkX: landmark) {
                let track = CALayer()
                track.backgroundColor = NSColor(calibratedRed: 0.30, green: 0.47, blue: 0.57, alpha: 0.7).cgColor
                track.cornerRadius = 1.5
                track.frame = CGRect(x: CGFloat(printAt.x) - 2, y: size.height - CGFloat(printAt.y), width: 4, height: 2.5)
                view.layer?.insertSublayer(track, at: 0)
                footprints.append((track, 0))
                if footprints.count > 72 { footprints.removeFirst().layer.removeFromSuperlayer() }
            }
            states[index] = residents[index].state
            let resident = residents[index]
            let height = CGFloat(resident.state.bodySize.y)
            let width = CGFloat(resident.state.bodySize.x)
            resident.character.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let social = resident.state.watchingCursor || resident.state.greetingFriend || resident.state.visitingVillage
            let bob = reducedMotion || !resident.state.isWalking ? 0 : abs(sin(CGFloat(resident.state.phase))) * 1.5
            resident.character.position = CGPoint(x: CGFloat(resident.state.x), y: height / 2 + 2 + bob)
            // The fox artwork faces left at its native orientation.
            let facing = resident.state.direction * (resident.kind == .fox ? -1 : 1)
            resident.character.setAffineTransform(CGAffineTransform(scaleX: CGFloat(facing), y: 1))
            resident.character.isHidden = !resident.state.isVisible
            resident.bubble.string = resident.state.watchingCursor ? "?" : (resident.state.greetingFriend ? "♥" : "…")
            resident.bubble.position = CGPoint(x: CGFloat(resident.state.x) + 10, y: height + 16)
            resident.bubble.isHidden = !resident.state.isVisible || !social
        }
    }
}
