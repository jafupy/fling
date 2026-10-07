import CoreGraphics
import Foundation

enum ScaleGesture {
    static func notches(radii: [Int32: Double], anchor: [Int32: Double],
                        aggregateDelta: Double, threshold: Double) -> Int {
        guard abs(aggregateDelta) >= threshold else { return 0 }
        let ratios = anchor.compactMap { id, radius -> Double? in
            guard radius > 0.0001, let current = radii[id] else { return nil }
            return current / radius
        }.sorted()
        guard ratios.count >= 3 else { return 0 }
        let growing = aggregateDelta > 0
        let agreeing = ratios.filter { growing ? $0 > 1 + threshold * 0.35 : $0 < 1 - threshold * 0.35 }
        guard agreeing.count >= 3 else { return 0 }
        let coherentRatio = growing ? ratios[ratios.count - 3] : ratios[2]
        let factor = growing ? 1 + threshold : 1 - threshold
        let count = max(1, min(16, Int(floor(log(max(0.0001, coherentRatio)) / log(factor)))))
        return growing ? count : -count
    }
}

struct ScrubGesture {
    private var origin: CGPoint?
    private var extremeX = 0.0
    private var direction = 0
    private var reversals = 0
    private var startedAt = 0.0

    mutating func update(centroid: CGPoint, timestamp: Double, distance: Double, spreadRatio: Double) -> Bool {
        guard abs(spreadRatio - 1) < 0.14 else {
            reset(at: centroid, timestamp: timestamp)
            return false
        }
        guard let origin else {
            reset(at: centroid, timestamp: timestamp)
            return false
        }
        let x = Double(centroid.x)
        if (direction != 0 && timestamp - startedAt > 0.7) ||
            abs(centroid.y - origin.y) > 0.08 || abs(centroid.x - origin.x) > 0.22 {
            reset(at: centroid, timestamp: timestamp)
            return false
        }
        if direction == 0 {
            let dx = x - Double(origin.x)
            if abs(dx) >= distance {
                direction = dx > 0 ? 1 : -1
                extremeX = x
                startedAt = timestamp
            }
            return false
        }
        if (x - extremeX) * Double(direction) > 0 {
            extremeX = x
        } else if abs(x - extremeX) >= distance {
            direction = -direction
            extremeX = x
            reversals += 1
        }
        return reversals >= 2
    }

    private mutating func reset(at point: CGPoint, timestamp: Double) {
        origin = point
        extremeX = Double(point.x)
        direction = 0
        reversals = 0
        startedAt = timestamp
    }
}

struct PinchRemovalGesture {
    private var anchorRadii: [Int32: Double] = [:]
    private var confirmationFrames = 0
    private(set) var isArmed = false

    mutating func update(radii: [Int32: Double]) {
        guard !anchorRadii.isEmpty else {
            anchorRadii = radii
            return
        }
        let ratios = anchorRadii.compactMap { id, radius -> Double? in
            guard radius > 0.0001, let current = radii[id] else { return nil }
            return current / radius
        }
        guard ratios.count == 4 else { return }
        let ratio = ratios.reduce(0, +) / Double(ratios.count)
        if isArmed {
            if ratio >= 0.88 { isArmed = false; confirmationFrames = 0 }
        } else if ratio <= 0.72, ratios.filter({ $0 <= 0.8 }).count >= 3 {
            confirmationFrames += 1
            if confirmationFrames >= 3 { isArmed = true }
        } else {
            confirmationFrames = 0
        }
    }

    mutating func reset(radii: [Int32: Double] = [:]) {
        anchorRadii = radii
        confirmationFrames = 0
        isArmed = false
    }
}
