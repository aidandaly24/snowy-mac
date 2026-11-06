#if DEBUG
import AppKit
import SnowCore

/// Render the actual native scenery and walkers without inspecting the user's desktop.
@MainActor
func renderVillagePreview(to path: String) throws {
    let widths: [CGFloat] = [1470, 1024]
    let rowHeight: CGFloat = 250
    let root = NSView(frame: CGRect(x: 0, y: 0, width: widths[0], height: rowHeight * CGFloat(widths.count)))
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.20, blue: 0.28, alpha: 1).cgColor
    let window = NSWindow(contentRect: root.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = root
    var retained: [AnyObject] = []
    for (index, width) in widths.enumerated() {
        let size = CGSize(width: width, height: rowHeight - 30)
        let row = NSView(frame: CGRect(x: 0, y: rowHeight * CGFloat(widths.count - 1 - index), width: width, height: size.height))
        row.wantsLayer = true
        root.addSubview(row)
        let dock = CGRect(x: width * 0.34, y: size.height - 65, width: width * 0.34, height: 65)
        let dockLayer = CALayer()
        dockLayer.frame = CGRect(x: dock.minX, y: 0, width: dock.width, height: dock.height)
        dockLayer.backgroundColor = NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.39, alpha: 1).cgColor
        dockLayer.cornerRadius = 12
        row.layer?.addSublayer(dockLayer)
        let desktop = SceneDesktop(id: UInt32(index + 1), size: size, dock: dock, anchors: [])
        let scene = DesktopVibe.cozyVillage.decorations(in: desktop, fallback: DecorationConfiguration()).scene(for: desktop)
        let frames = scene.props.compactMap { prop -> CGRect? in
            guard let piece = DecorationCatalog.piece(prop.assetID) else { return nil }
            return DecorationPlacement.frame(for: prop, piece: piece, desktopSize: size, dock: dock)
        }
        for first in frames.indices {
            for second in frames.indices where second > first {
                precondition(!frames[first].insetBy(dx: 0.5, dy: 0.5).intersects(frames[second].insetBy(dx: 0.5, dy: 0.5)),
                             "Cozy props overlap at width \(width)")
            }
        }
        let decorations = DesktopDecorations(size: size)
        decorations.updateDock(dock)
        decorations.configure(props: scene.props)
        row.addSubview(decorations.view)
        let friends = WinterFriendView(size: size)
        friends.count = 5
        row.addSubview(friends.view)
        let bodies = [SolidBody(id: 1, bounds: dock)]
        for frame in 0..<360 {
            friends.advance(now: Double(frame) / 30, cursor: nil, bodies: bodies, reducedMotion: false,
                            landmarks: scene.props.map { Float($0.x * width) })
        }
        retained.append(decorations)
        retained.append(friends)
        let label = NSTextField(labelWithString: "Cozy Village · \(Int(width)) pt · five friends")
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = CGRect(x: 16, y: row.frame.maxY + 5, width: width - 32, height: 20)
        root.addSubview(label)
    }
    root.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
    root.cacheDisplay(in: root.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try png.write(to: URL(fileURLWithPath: path))
    withExtendedLifetime(retained) {}
    window.close()
}
#endif
