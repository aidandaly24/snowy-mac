import Foundation
import SnowCore

struct SavedDesktopVibe: Codable {
    var scene: DecorationScene
    var snowfall: String
    var windX: Float
    var windY: Float
    var friendKind: String
    var friendCount: Int
    // Optional for compatibility with presets saved before this control existed.
    var lightSnowCatch: Float? = nil

    var lightSnowCatchFraction: Float {
        guard let value = lightSnowCatch, value.isFinite else { return 0.2 }
        return min(1, max(0, value))
    }

    var weather: Snowfall { Snowfall(rawValue: snowfall) ?? .light }
    var wind: WindSettings { WindSettings(vector: SIMD2(windX, windY)) }
    var friends: WinterFriendKind { WinterFriendKind(rawValue: friendKind) ?? .mixed }
}
