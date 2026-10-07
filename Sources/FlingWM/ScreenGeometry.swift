import AppKit

struct ScreenGeometry {
    let screen: NSScreen
    let frame: CGRect
    let availableFrame: CGRect

    static func screenContaining(quartzPoint: CGPoint) -> ScreenGeometry? {
        let cocoaPoint = quartzToCocoa(quartzPoint)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) }) ?? NSScreen.main else {
            return nil
        }

        let frame = cocoaToQuartz(screen.frame)
        var available = cocoaToQuartz(screen.visibleFrame)
        let insets = StageManager.shared.reservedInsets(on: frame)
        available.origin.x += insets.left
        available.size.width -= insets.left + insets.right
        available.size.width = max(100, available.width)
        return ScreenGeometry(screen: screen, frame: frame, availableFrame: available)
    }

    static func currentPointer() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func cocoaToQuartz(_ rect: CGRect) -> CGRect {
        let top = mainScreenTop
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzToCocoa(_ rect: CGRect) -> CGRect {
        let top = mainScreenTop
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzToCocoa(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenTop - point.y)
    }

    private static var mainScreenTop: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }
}
