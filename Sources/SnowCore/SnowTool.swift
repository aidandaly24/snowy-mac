public enum SnowTool: String, CaseIterable, Sendable {
    case glove = "Glove"
    case shovel = "Shovel"
    case snowball = "Snowball"
    case snowman = "Build Snowman"

    public var radius: Float { self == .shovel ? 36 : 24 }
}
