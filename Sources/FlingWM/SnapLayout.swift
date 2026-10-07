import AppKit

enum SnapZone: Equatable, CaseIterable {
    case left
    case right
    case top
    case bottom
    case center
    case full

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .center: return "Centre"
        case .full: return "Full"
        }
    }

    var isEdge: Bool { self != .center && self != .full }
}

enum SnapLayout {
    private static let snapDetectionTolerance: CGFloat = 18

    static func padded(_ frame: CGRect, settings: FlingSettings) -> CGRect {
        var result = frame.insetBy(dx: settings.horizontalPadding, dy: settings.verticalPadding)
        if result.width < 160 || result.height < 120 {
            result = frame
        }
        return result
    }

    static func frameFor(zone: SnapZone, size: CGFloat, in available: CGRect, gap: CGFloat) -> CGRect {
        let halfGap = max(0, gap) / 2
        switch zone {
        case .full:
            return available.integral
        case .left:
            let width = max(120, floor(available.width * size - halfGap))
            return CGRect(x: available.minX, y: available.minY, width: width, height: available.height).integral

        case .right:
            let width = max(120, floor(available.width * size - halfGap))
            return CGRect(x: available.maxX - width, y: available.minY, width: width, height: available.height).integral

        case .top:
            let height = max(100, floor(available.height * size - halfGap))
            return CGRect(x: available.minX, y: available.minY, width: available.width, height: height).integral

        case .bottom:
            let height = max(100, floor(available.height * size - halfGap))
            return CGRect(x: available.minX, y: available.maxY - height, width: available.width, height: height).integral

        case .center:
            let width = min(available.width, max(180, available.width * size))
            let height = min(available.height, max(120, available.height * size))
            return CGRect(
                x: available.midX - width / 2,
                y: available.midY - height / 2,
                width: width,
                height: height
            ).integral
        }
    }

    static func labelFor(zone: SnapZone, size: CGFloat) -> String {
        if zone == .full { return "Full" }
        let percent = Int((size * 100).rounded())
        return "\(zone.label) \(percent)%"
    }

    static func inferInitialState(frame: CGRect?, pointer: CGPoint) -> (zone: SnapZone?, sizeOffset: Int) {
        guard let frame,
              let screen = ScreenGeometry.screenContaining(quartzPoint: pointer)
        else { return (nil, 0) }

        let settings = SettingsStore.shared.snapshot()
        let available = padded(screen.availableFrame, settings: settings)

        if frameError(frame, available.integral) <= snapDetectionTolerance { return (.full, 0) }

        var best: (zone: SnapZone, index: Int, error: CGFloat)?

        for zone in SnapZone.allCases {
            let sizes: [CGFloat] = zone == .full ? [1] : zone.isEdge ? settings.edgeSizes : settings.centerSizes
            for (index, size) in sizes.enumerated() {
                let candidate = frameFor(zone: zone, size: size, in: available, gap: settings.windowGap)
                let error = frameError(frame, candidate)
                if error <= snapDetectionTolerance,
                   best == nil || error < best!.error {
                    best = (zone, index, error)
                }
            }
        }

        guard let best else { return (nil, 0) }
        let base = best.zone == .full ? 0 : best.zone.isEdge ? settings.edgeDefaultIndex : settings.centerDefaultIndex
        return (best.zone, best.index - base)
    }

    static func frameError(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(
            max(abs(a.minX - b.minX), abs(a.minY - b.minY)),
            max(abs(a.width - b.width), abs(a.height - b.height))
        )
    }

}
