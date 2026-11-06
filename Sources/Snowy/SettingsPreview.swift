#if DEBUG
import AppKit
import SnowCore

/// Offscreen layout verification for the personal settings window.
@MainActor
func renderSettingsPreview(to path: String) throws {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let settings = DecorationSettings()
    let desktop = SceneDesktop(id: 1, size: CGSize(width: 1512, height: 982), dock: nil, anchors: [])
    settings.desktops = [desktop]
    settings.load(DesktopVibe.cozyVillage.decorations(in: desktop, fallback: DecorationConfiguration()))
    settings.loadControls(vibe: .cozyVillage, snowfall: .light, wind: DesktopVibe.cozyVillage.wind,
                          friendKind: .mixed, friendCount: 3, battery: false, saved: false)
    // Exercise the real native preset data and friend-layer lifecycle before rendering.
    let usedAssets = Set(DesktopVibe.allCases.flatMap { $0.assets.map { $0.0 } })
    precondition(DecorationCatalog.all.allSatisfy { usedAssets.contains($0.id) || $0.id == "Winter penguin" || $0.id == "Winter fox" })
    for vibe in DesktopVibe.allCases where vibe != .custom {
        let scene = vibe.decorations(in: desktop, fallback: DecorationConfiguration()).scene(for: desktop)
        precondition(scene.props.allSatisfy { DecorationCatalog.piece($0.assetID) != nil })
        let preset = SavedDesktopVibe(scene: scene, snowfall: vibe.snowfall.rawValue,
                                     windX: vibe.wind.vector.x, windY: vibe.wind.vector.y,
                                     friendKind: WinterFriendKind.mixed.rawValue, friendCount: 3, lightSnowCatch: 0.35)
        let roundtrip = try JSONDecoder().decode(SavedDesktopVibe.self, from: JSONEncoder().encode(preset))
        precondition(roundtrip.scene == scene && roundtrip.friends == .mixed && roundtrip.lightSnowCatchFraction == 0.35)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as! [String: Any]
        legacy.removeValue(forKey: "lightSnowCatch")
        let oldPreset = try JSONDecoder().decode(SavedDesktopVibe.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldPreset.scene == scene && oldPreset.lightSnowCatchFraction == 0.2)
    }
    let friends = WinterFriendView(size: desktop.size)
    for kind in WinterFriendKind.allCases {
        friends.kind = kind
        for count in 1...5 {
            friends.count = count
            friends.advance(now: Double(count), cursor: nil, bodies: [], reducedMotion: false)
        }
    }
    let controller = SnowyWindowController(settings: settings, resetDecorations: {}, replayWalkthrough: {})
    guard let window = controller.window, let view = window.contentView else { return }
    window.setContentSize(CGSize(width: 1000, height: 760))
    window.appearance = NSAppearance(named: .darkAqua)
    view.appearance = NSAppearance(named: .darkAqua)
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    window.appearance?.performAsCurrentDrawingAppearance {
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try png.write(to: URL(fileURLWithPath: path))
    window.close()
}
#endif
