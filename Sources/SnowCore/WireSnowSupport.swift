import Foundation

public enum WireSnowSupport {
    public static func build(id: UInt64, points input: [SIMD2<Float>], size: SIMD2<Float>,
                             occluders: [SolidBody], catchFraction: Float = 0.2) -> Surface? {
        guard catchFraction.isFinite, (0...1).contains(catchFraction) else { return nil }
        guard size.x.isFinite, size.y.isFinite, size.x > 8, size.y > 8 else { return nil }
        let points = Array(input.prefix(256).filter { $0.x.isFinite && $0.y.isFinite })
        guard points.count >= 2, let lowX = points.map(\.x).min(), let highX = points.map(\.x).max() else { return nil }
        let left = max(0, lowX), right = min(size.x, highX), width = right - left
        guard width >= 8 else { return nil }
        let count = 48
        var heights: [Float] = []
        for index in 0..<count {
            let x = left + width * Float(index) / Float(count - 1)
            var upper: Float?
            for pair in zip(points, points.dropFirst()) {
                let dx = pair.1.x - pair.0.x
                guard abs(dx) > 0.001, x >= min(pair.0.x, pair.1.x) - 0.01,
                      x <= max(pair.0.x, pair.1.x) + 0.01 else { continue }
                let fraction = max(0, min(1, (x - pair.0.x) / dx))
                let y = pair.0.y + (pair.1.y - pair.0.y) * fraction
                upper = min(upper ?? y, y)
            }
            guard let upper else { return nil }
            heights.append((max(0, min(size.y, upper)) * 2).rounded() / 2)
        }
        let base = heights.min() ?? 0
        let offsets = heights.map { $0 - base }
        var visible: [Span] = [], exposed: [Span] = []
        func append(_ span: Span, to spans: inout [Span]) {
            if let last = spans.last, abs(last.upper - span.lower) < 0.01 { spans[spans.count - 1].upper = span.upper }
            else { spans.append(span) }
        }
        for index in 0..<(count - 1) {
            let lower = width * Float(index) / Float(count - 1)
            let upper = width * Float(index + 1) / Float(count - 1)
            let point = SIMD2(left + (lower + upper) / 2, (heights[index] + heights[index + 1]) / 2)
            let covered = occluders.prefix(64).contains { $0.contains(point) }
            let roof = occluders.prefix(64).contains {
                point.x >= Float($0.bounds.minX) && point.x <= Float($0.bounds.maxX) && Float($0.bounds.minY) < point.y
            }
            if !covered { append(Span(lower, upper), to: &visible) }
            if !covered && !roof { append(Span(lower, upper), to: &exposed) }
        }
        return Surface(id: id, x: left, y: base, width: width, visibleSpans: visible,
                       snowfallSpans: exposed, releasesSnowWhenRemoved: true, isElevated: false,
                       supportOffsets: offsets, maximumSnowDepth: 3, snowCatchFraction: catchFraction)
    }
}
