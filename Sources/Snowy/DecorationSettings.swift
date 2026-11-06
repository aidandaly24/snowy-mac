import Foundation
import Observation
import SnowCore

@MainActor
@Observable
final class DecorationSettings {
    static let scaleRange = 0.65...1.60
    var vibe: DesktopVibe = .cozyVillage { didSet { if !isSynchronizing { notice = ""; onVibeChange?(vibe) } } }
    var snowfall: Snowfall = .light { didSet { sendWeather() } }
    var windHeading: Double = 90 { didSet { sendWeather() } }
    var windStrength: Double = 0.08 { didSet { sendWeather() } }
    var friendKind: WinterFriendKind = .mixed { didSet { sendFriends() } }
    var friendCount = 3 { didSet { sendFriends() } }
    var lightSnowCatch: Double = 0.2 {
        didSet {
            if !isSynchronizing { notice = ""; onLightSnowCatchChange?(Float(lightSnowCatch)) }
        }
    }
    var batteryFriendly = false { didSet { if !isSynchronizing { onBatteryChange?(batteryFriendly) } } }
    var tool: SnowTool = .glove { didSet { if !isSynchronizing { onToolChange?(tool) } } }
    var hasSavedVibe = false
    var savedPresetAssets: [String: [String]] = [:]
    var notice = ""

    private(set) var layout: DecorationLayout
    var scale: Double {
        didSet {
            guard !isSynchronizing, scale != oldValue else { return }
            defaults.set(scale, forKey: "decorations.scale")
            apply()
        }
    }
    var pushes: Bool {
        didSet {
            guard !isSynchronizing, pushes != oldValue else { return }
            defaults.set(pushes, forKey: "decorations.pushes")
            apply()
        }
    }
    private(set) var usesCustomScenes: Bool
    private(set) var scenes: [UInt32: DecorationScene]
    var includesDesktopIcons: Bool {
        didSet {
            guard !isSynchronizing, includesDesktopIcons != oldValue else { return }
            defaults.set(includesDesktopIcons, forKey: "decorations.includesDesktopIcons")
            apply()
        }
    }
    var desktops: [SceneDesktop] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isSynchronizing = false
    @ObservationIgnored var onChange: ((DecorationConfiguration) -> Void)?
    @ObservationIgnored var onEditorVisibility: ((Bool) -> Void)?
    @ObservationIgnored var onVibeChange: ((DesktopVibe) -> Void)?
    @ObservationIgnored var onWeatherChange: ((Snowfall, WindSettings) -> Void)?
    @ObservationIgnored var onFriendsChange: ((WinterFriendKind, Int) -> Void)?
    @ObservationIgnored var onLightSnowCatchChange: ((Float) -> Void)?
    @ObservationIgnored var onBatteryChange: ((Bool) -> Void)?
    @ObservationIgnored var onSaveVibe: (() -> Bool)?
    @ObservationIgnored var onResetVibe: (() -> Void)?
    @ObservationIgnored var onToolChange: ((SnowTool) -> Void)?
    @ObservationIgnored var onClearSnow: (() -> Void)?
    @ObservationIgnored var onResetPositions: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = DecorationLayout(rawValue: defaults.string(forKey: "decorations.layout") ?? "") ?? .none
        let savedScale = defaults.object(forKey: "decorations.scale") as? Double ?? 1
        scale = savedScale.isFinite ? min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, savedScale)) : 1
        pushes = (defaults.object(forKey: "decorations.pushes") as? Bool) ?? defaults.bool(forKey: "decorations.canTopple")
        includesDesktopIcons = defaults.bool(forKey: "decorations.includesDesktopIcons")
        let savedScenes: [UInt32: DecorationScene]
        if let data = defaults.data(forKey: "decorations.scenes"), data.count <= 256_000,
           let restored = try? JSONDecoder().decode([UInt32: DecorationScene].self, from: data) {
            savedScenes = restored.mapValues { $0.bounded() }
        } else {
            savedScenes = [:]
        }
        scenes = savedScenes
        usesCustomScenes = !savedScenes.isEmpty && defaults.bool(forKey: "decorations.usesCustomScenes")
    }

    var configuration: DecorationConfiguration {
        DecorationConfiguration(layout: layout, scale: scale, pushes: pushes, usesCustomScenes: usesCustomScenes,
                                scenes: scenes, includesDesktopIcons: includesDesktopIcons)
    }

    func selectPreset(_ preset: DecorationLayout) {
        guard layout != preset || usesCustomScenes else { return }
        layout = preset
        usesCustomScenes = false
        defaults.set(preset.rawValue, forKey: "decorations.layout")
        defaults.set(false, forKey: "decorations.usesCustomScenes")
        apply()
    }

    func saveScenes(_ drafts: [UInt32: DecorationScene]) -> Bool {
        let updated = scenes.merging(drafts.mapValues { $0.bounded() }, uniquingKeysWith: { _, draft in draft })
        guard !updated.isEmpty, let data = try? JSONEncoder().encode(updated), data.count <= 256_000 else { return false }
        scenes = updated
        usesCustomScenes = true
        defaults.set(data, forKey: "decorations.scenes")
        defaults.set(true, forKey: "decorations.usesCustomScenes")
        apply()
        return true
    }

    func load(_ configuration: DecorationConfiguration) {
        guard self.configuration != configuration else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        layout = configuration.layout
        scale = configuration.scale
        pushes = configuration.pushes
        usesCustomScenes = configuration.usesCustomScenes
        scenes = configuration.scenes
        includesDesktopIcons = configuration.includesDesktopIcons
    }

    func apply() { if !isSynchronizing { onChange?(configuration) } }

    func loadControls(vibe: DesktopVibe, snowfall: Snowfall, wind: WindSettings,
                      friendKind: WinterFriendKind, friendCount: Int, battery: Bool, saved: Bool, tool: SnowTool = .glove, lightSnowCatch: Float = 0.2) {
        if self.vibe != vibe { notice = "" }
        guard self.vibe != vibe || self.snowfall != snowfall || self.friendKind != friendKind
            || self.friendCount != friendCount || batteryFriendly != battery || hasSavedVibe != saved || self.tool != tool
            || abs(self.lightSnowCatch - Double(lightSnowCatch)) > 0.00001
            || abs(windHeading - Double(wind.headingDegrees)) > 0.0001
            || abs(windStrength - Double(wind.speedFraction)) > 0.00001 else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        self.vibe = vibe
        self.snowfall = snowfall
        windHeading = Double(wind.headingDegrees)
        windStrength = Double(wind.speedFraction)
        self.friendKind = friendKind
        self.friendCount = friendCount
        batteryFriendly = battery
        hasSavedVibe = saved
        self.tool = tool
        self.lightSnowCatch = Double(lightSnowCatch)
    }

    private func sendWeather() {
        guard !isSynchronizing else { return }
        notice = ""
        onWeatherChange?(snowfall, WindSettings(headingDegrees: Float(windHeading), speedFraction: Float(windStrength)))
    }

    private func sendFriends() {
        guard !isSynchronizing else { return }
        notice = ""
        onFriendsChange?(friendKind, min(5, max(1, friendCount)))
    }
}
