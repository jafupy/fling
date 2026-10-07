import CoreGraphics

struct FlingPosition {
    enum Axis { case horizontal, vertical }
    struct Movement {
        let axis: Axis
        let direction: Int
        let steps: Int
        let beginsStroke: Bool
    }

    private var anchor: CGPoint
    private var axis: Axis?
    private var lastMotionPoint: CGPoint
    private var lastMotionAt: Double?
    private var lastDirection: Int?
    private var lastAxis: Axis?
    private var pendingStroke = false

    init(origin: CGPoint) { anchor = origin; lastMotionPoint = origin }

    mutating func reanchor(at point: CGPoint) { anchor = point }

    mutating func update(at point: CGPoint, timestamp: Double, threshold: Double) -> Movement? {
        if let lastMotionAt, timestamp - lastMotionAt >= 0.15 { pendingStroke = true }
        if lastMotionAt == nil || hypot(point.x - lastMotionPoint.x, point.y - lastMotionPoint.y) >= 0.002 {
            lastMotionPoint = point
            lastMotionAt = timestamp
        }
        let dx = Double(point.x - anchor.x)
        let dy = Double(point.y - anchor.y)
        guard max(abs(dx), abs(dy)) >= threshold else { return nil }

        if let axis {
            let along = axis == .horizontal ? abs(dx) : abs(dy)
            let across = axis == .horizontal ? abs(dy) : abs(dx)
            // A deliberate turn changes axes; small diagonal drift does not.
            if across >= threshold * 1.8, across > along * 1.5 {
                self.axis = axis == .horizontal ? .vertical : .horizontal
            }
        } else {
            axis = abs(dx) >= abs(dy) ? .horizontal : .vertical
        }

        guard let axis else { return nil }
        let distance = axis == .horizontal ? dx : dy
        let steps = Int(abs(distance) / threshold)
        guard steps > 0 else { return nil }
        let direction = distance > 0 ? 1 : -1
        let advance = Double(steps * direction) * threshold
        if axis == .horizontal {
            anchor.x += advance
            anchor.y = point.y
        } else {
            anchor.y += advance
            anchor.x = point.x
        }
        let beginsStroke = pendingStroke || lastAxis != axis || lastDirection != direction
        pendingStroke = false
        lastAxis = axis
        lastDirection = direction
        return Movement(axis: axis, direction: direction, steps: steps, beginsStroke: beginsStroke)
    }

    static func destination(zone: SnapZone?, offset: Int, movement: Movement,
                            fullBoundaryDirection: Int?,
                            settings: FlingSettings) -> (zone: SnapZone, offset: Int) {
        let near: SnapZone = movement.axis == .horizontal ? .left : .top
        let far: SnapZone = movement.axis == .horizontal ? .right : .bottom
        // Raw trackpad Y increases upwards; screen order runs top to bottom.
        let direction = movement.axis == .horizontal ? movement.direction : -movement.direction
        let count = settings.edgeSizes.count
        let center = count + 1
        let last = count * 2 + 2
        let index: Int
        if zone == .full, let boundary = fullBoundaryDirection {
            index = boundary < 0 ? 0 : last
        } else if zone == near {
            index = 1 + max(0, min(count - 1, settings.edgeDefaultIndex + offset))
        } else if zone == .center {
            index = center
        } else if zone == far {
            index = center + count - max(0, min(count - 1, settings.edgeDefaultIndex + offset))
        } else {
            // A full or unsnapped window enters the side actually flung towards.
            let first = direction > 0 ? center + count - settings.edgeDefaultIndex : 1 + settings.edgeDefaultIndex
            return destination(at: max(0, min(last, first + (movement.steps - 1) * direction)),
                               near: near, far: far, settings: settings)
        }
        return destination(at: max(0, min(last, index + movement.steps * direction)),
                           near: near, far: far, settings: settings)
    }

    private static func destination(at index: Int, near: SnapZone, far: SnapZone,
                                    settings: FlingSettings) -> (zone: SnapZone, offset: Int) {
        let center = settings.edgeSizes.count + 1
        if index == 0 || index == center * 2 { return (.full, 0) }
        if index == center { return (.center, 0) }
        if index < center { return (near, index - 1 - settings.edgeDefaultIndex) }
        return (far, center + settings.edgeSizes.count - index - settings.edgeDefaultIndex)
    }
}
