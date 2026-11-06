import Foundation

public enum DesktopVibe: String, CaseIterable, Codable, Sendable {
    case cozyVillage = "Cozy Village"
    case blizzard = "Blizzard"
    case citySnowfall = "City Snowfall"
    case christmasMorning = "Christmas Morning"
    case winterMarket = "Winter Market"
    case alpineRetreat = "Alpine Retreat"
    case lanternGarden = "Lantern Garden"
    case gingerbreadLane = "Gingerbread Lane"
    case custom = "Custom"

    public var snowfall: Snowfall {
        switch self {
        case .blizzard: .blizzard
        case .citySnowfall, .alpineRetreat: .steady
        default: .light
        }
    }
    public var wind: WindSettings {
        self == .blizzard ? WindSettings(vector: SIMD2(0.94, 0.22)) : WindSettings(vector: SIMD2(0.08, 0.02))
    }
}
