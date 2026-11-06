import Foundation
import SnowCore

extension DesktopVibe {
    var detail: String {
        switch self {
        case .cozyVillage: "A continuous village, with a cozy café above the Dock."
        case .blizzard: "Windswept chalets, drifting powder and strong gusts."
        case .citySnowfall: "Brownstones, streetlamps and a snowy city block."
        case .christmasMorning: "A decorated fir, wrapped gifts and colored lights."
        case .winterMarket: "A cocoa stand, chalkboard and village square."
        case .alpineRetreat: "Mountain chalets, pines, sleds and snowmen."
        case .lanternGarden: "Evergreens, a quiet bench and candlelight."
        case .gingerbreadLane: "Candy canes, gifts and gingerbread neighbors."
        case .custom: "Your own scene."
        }
    }

    var assets: [(String, Double)] {
        switch self {
        case .cozyVillage:
            [("Frosted pine", 0.025), ("Alpine chalet", 0.12), ("Holiday mailbox", 0.22),
             ("Candle lantern", 0.29), ("Cocoa stall", 0.38), ("Cocoa chalkboard", 0.46),
             ("Corner streetlamp", 0.52), ("Snowy park bench", 0.61), ("Alpine chalet", 0.73),
             ("Snowman", 0.83), ("Frosted pine", 0.93)]
        case .blizzard:
            [("Frosted pine", 0.025), ("Alpine chalet", 0.10), ("Wooden sled", 0.18),
             ("Snowman", 0.24), ("Holiday mailbox", 0.78), ("Alpine chalet", 0.85),
             ("Frosted pine", 0.94), ("Candle lantern", 0.98)]
        case .citySnowfall:
            [("Corner streetlamp", 0.025), ("Holiday brownstone", 0.10), ("Red fire hydrant", 0.18),
             ("Snowy park bench", 0.27), ("Holiday mailbox", 0.78), ("Holiday brownstone", 0.87), ("Corner streetlamp", 0.96)]
        case .christmasMorning:
            [("Red present", 0.025), ("Decorated fir", 0.09), ("Blue present", 0.16), ("Candy cane", 0.23),
             ("Gingerbread friend", 0.78), ("Red present", 0.84), ("Decorated fir", 0.91), ("Blue present", 0.975)]
        case .winterMarket:
            [("Corner streetlamp", 0.025), ("Cocoa chalkboard", 0.065), ("Cocoa stall", 0.14),
             ("Cocoa supplies", 0.22), ("Candy cane", 0.27), ("Snowy park bench", 0.79),
             ("Cocoa stall", 0.88), ("Candle lantern", 0.97)]
        case .alpineRetreat:
            [("Frosted pine", 0.025), ("Alpine chalet", 0.10), ("Wooden sled", 0.18),
             ("Snowman", 0.25), ("Alpine chalet", 0.84), ("Frosted pine", 0.92), ("Candle lantern", 0.98)]
        case .lanternGarden:
            [("Potted evergreen", 0.025), ("Candle lantern", 0.07), ("Snowy park bench", 0.14),
             ("Potted evergreen", 0.21), ("Candle lantern", 0.27), ("Frosted pine", 0.79),
             ("Snowy park bench", 0.86), ("Potted evergreen", 0.93), ("Candle lantern", 0.98)]
        case .gingerbreadLane:
            [("Candy cane", 0.025), ("Gingerbread friend", 0.08), ("Red present", 0.13),
             ("Alpine chalet", 0.20), ("Blue present", 0.27), ("Decorated fir", 0.80),
             ("Gingerbread friend", 0.87), ("Candy cane", 0.94), ("Candle lantern", 0.98)]
        case .custom: []
        }
    }

    var previewPieces: [DecorationPiece] {
        var seen = Set<String>()
        return assets.compactMap { name, _ in seen.insert(name).inserted ? DecorationCatalog.piece(name) : nil }
    }

    func decorations(in desktop: SceneDesktop, fallback: DecorationConfiguration) -> DecorationConfiguration {
        guard self != .custom else { return fallback }
        let pieces = assets
        let props = self == .cozyVillage ? cozyVillageProps(in: desktop)
            : pieces.map { name, x in PlacedDecoration(assetID: name, x: x, scale: 1, pushes: false) }
        let lights: [LightString] = self != .blizzard ? [LightString(anchors: [
            LightAnchor(fallback: CGPoint(x: 0, y: 0.10), attachment: .desktop(edge: .left, fraction: 0.10)),
            LightAnchor(fallback: CGPoint(x: 1, y: 0.10), attachment: .desktop(edge: .right, fraction: 0.10))
        ], palette: self == .christmasMorning || self == .gingerbreadLane ? .classic : .warmWhite, slack: 0.14)] : []
        return DecorationConfiguration(usesCustomScenes: true,
                                       scenes: [desktop.id: DecorationScene(props: props, lights: lights)])
    }

    private func cozyVillageProps(in desktop: SceneDesktop) -> [PlacedDecoration] {
        let pieces = assets.compactMap { DecorationCatalog.piece($0.0) }
        let margin: CGFloat = 18
        let gap: CGFloat = 14
        let width = max(1, desktop.size.width)
        var rails: [(left: CGFloat, right: CGFloat, support: DecorationSupport)] = []
        if let dock = desktop.dock?.intersection(CGRect(origin: .zero, size: desktop.size)),
           !dock.isEmpty, dock.minY > 0 {
            rails.append((margin, dock.minX - gap, .floor))
            let top = DecorationPlacement.rail(for: .dock, desktopSize: desktop.size, dock: dock)
            rails.append((top.minX + 6, top.maxX - 6, .dock))
            rails.append((dock.maxX + gap, width - margin, .floor))
        } else {
            rails.append((margin, width - margin, .floor))
        }
        rails = rails.filter { $0.right - $0.left > 20 }
        var result: [PlacedDecoration] = []
        // Fit the actual pixel-art widths to the available rails, including the Dock.
        // Smaller displays get a coherent scaled village rather than overlapping props.
        for attempt in 0...7 {
            let scale = 1 - CGFloat(attempt) * 0.05
            var next = 0
            result.removeAll(keepingCapacity: true)
            for rail in rails {
                let available = rail.right - rail.left
                let first = next
                var groupWidth: CGFloat = 0
                while next < pieces.count {
                    let itemWidth = CGFloat(pieces[next].width) * 3 * scale
                    let required = itemWidth + (next > first ? gap : 0)
                    guard groupWidth + required <= available else { break }
                    groupWidth += required
                    next += 1
                }
                guard next > first else { continue }
                let count = next - first
                let artWidth = groupWidth - CGFloat(count - 1) * gap
                let spacing = count > 1 ? min(34, (available - artWidth) / CGFloat(count - 1)) : 0
                groupWidth = artWidth + CGFloat(count - 1) * spacing
                var left = rail.left + (available - groupWidth) / 2
                for piece in pieces[first..<next] {
                    let itemWidth = CGFloat(piece.width) * 3 * scale
                    let ordinal = UInt8(result.count)
                    let id = UUID(uuid: (0xA2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ordinal))
                    result.append(PlacedDecoration(id: id, assetID: piece.id, x: Double((left + itemWidth / 2) / width),
                                                   scale: Double(scale), pushes: false, support: rail.support))
                    left += itemWidth + spacing
                }
            }
            if next == pieces.count { break }
        }
        return result
    }

}
