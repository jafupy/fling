import AppKit
import CoreGraphics
import ApplicationServices

struct StagePreview {
    let bounds: CGRect
}

final class StageManager {
    static let shared = StageManager()
    private var isDragging = false
    private init() {}

    var isEnabled: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    func preview(at point: CGPoint) -> StagePreview? {
        guard isEnabled else { return nil }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in info {
            guard (window[kCGWindowOwnerName as String] as? String) == "WindowManager" else { continue }
            guard let bounds = windowBounds(window) else { continue }
            guard bounds.width > 40, bounds.height > 40, bounds.contains(point) else { continue }
            return StagePreview(bounds: bounds)
        }

        return nil
    }

    func reservedInsets(on screenFrame: CGRect) -> (left: CGFloat, right: CGFloat) {
        guard isEnabled else { return (0, 0) }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return (0, 0)
        }

        var left: CGFloat = 0
        var right: CGFloat = 0

        for window in info {
            guard (window[kCGWindowOwnerName as String] as? String) == "WindowManager" else { continue }
            guard let bounds = windowBounds(window) else { continue }
            guard bounds.width > 40, bounds.height > 40 else { continue }
            guard bounds.width < screenFrame.width * 0.4 else { continue }
            guard bounds.intersects(screenFrame) else { continue }

            if bounds.midX < screenFrame.midX,
               bounds.minX <= screenFrame.minX + 320 {
                left = max(left, bounds.maxX - screenFrame.minX + 12)
            } else if bounds.midX >= screenFrame.midX,
                      bounds.maxX >= screenFrame.maxX - 320 {
                right = max(right, screenFrame.maxX - bounds.minX + 12)
            }
        }

        return (min(left, 360), min(right, 360))
    }

    /// Dragging a Stage Manager preview into the stage adds it to the currently
    /// active group. A plain click would switch to that preview's group instead.
    func addPreviewToCurrentSet(at point: CGPoint, completion: @escaping (Bool) -> Void) {
        guard let geometry = ScreenGeometry.screenContaining(quartzPoint: point) else {
            completion(false)
            return
        }

        let destination = CGPoint(
            x: geometry.availableFrame.midX,
            y: geometry.availableFrame.midY
        )

        drag(from: point, to: destination, hold: 0) { succeeded in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { completion(succeeded) }
        }
    }

    func canRemoveWindowFromCurrentSet(_ window: AXUIElement) -> Bool {
        isEnabled && AXIsProcessTrusted() && !titlebarCandidates(of: window).isEmpty
    }

    /// Stage Manager has no public group API. Use its normal title-bar drag to
    /// the recent-apps strip, and confirm that the window leaves the stage.
    func removeWindowFromCurrentSet(_ window: AXUIElement, completion: @escaping (Bool) -> Void) {
        guard canRemoveWindowFromCurrentSet(window),
              let point = titlebarPoint(of: window),
              let geometry = ScreenGeometry.screenContaining(quartzPoint: point),
              let originalFrame = AccessibilityWindows.shared.frame(of: window),
              let windowID = onScreenWindowID(for: window)
        else {
            completion(false)
            return
        }

        let destination = stripDestination(on: geometry.frame)
        drag(from: point, to: destination, hold: 0.65) { dragged in
            guard dragged else {
                if let frame = AccessibilityWindows.shared.frame(of: window), frame != originalFrame {
                    AccessibilityWindows.shared.setFrame(originalFrame, of: window)
                }
                completion(false)
                return
            }
            self.confirmRemoval(windowID: windowID, window: window, originalFrame: originalFrame,
                                screenFrame: geometry.frame, attempts: 10, absentSamples: 0,
                                completion: completion)
        }
    }

    private func stripDestination(on screen: CGRect) -> CGPoint {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let previews = info.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerName as String] as? String) == "WindowManager",
                  let bounds = windowBounds(window), bounds.width > 40, bounds.height > 40,
                  bounds.width < screen.width * 0.4,
                  bounds.maxY > screen.minY, bounds.minY < screen.maxY else { return nil }
            return bounds
        }
        // Auto-hidden previews still have bounds just outside their screen edge.
        let leftDistance = previews.map { abs($0.midX - screen.minX) }.min() ?? .infinity
        let rightDistance = previews.map { abs($0.midX - screen.maxX) }.min() ?? .infinity
        let useRight = rightDistance < leftDistance && rightDistance < 360
        return CGPoint(x: useRight ? screen.maxX - 4 : screen.minX + 4, y: screen.midY)
    }

    private func confirmRemoval(windowID: CGWindowID, window: AXUIElement, originalFrame: CGRect,
                                screenFrame: CGRect, attempts: Int, absentSamples: Int,
                                completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
            let entry = info?.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }
            let bounds = entry.flatMap(self.windowBounds)
            let isThumbnail = bounds.map {
                $0.width < originalFrame.width * 0.75 && $0.height < originalFrame.height * 0.75 &&
                ($0.maxX < screenFrame.minX + 360 || $0.minX > screenFrame.maxX - 360)
            } ?? false
            // Stage Manager keeps the original window ID for its thumbnail.
            let leftStage = info != nil && (entry == nil || bounds.map { !$0.intersects(screenFrame) } == true || isThumbnail)
            let samples = leftStage ? absentSamples + 1 : 0
            if samples >= 2 { completion(true); return }
            if attempts > 1 {
                self.confirmRemoval(windowID: windowID, window: window, originalFrame: originalFrame,
                                    screenFrame: screenFrame, attempts: attempts - 1, absentSamples: samples,
                                    completion: completion)
                return
            }
            // Failed drags must not leave a window parked at the screen edge.
            if let frame = AccessibilityWindows.shared.frame(of: window), frame != originalFrame {
                AccessibilityWindows.shared.setFrame(originalFrame, of: window)
            }
            completion(false)
        }
    }

    private func drag(from point: CGPoint, to destination: CGPoint, hold: Double, completion: @escaping (Bool) -> Void) {
        guard isEnabled, AXIsProcessTrusted(), !isDragging,
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
              ),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: destination, mouseButton: .left)
        else {
            completion(false)
            return
        }

        let steps = 12
        let events = (1...steps).compactMap { step -> CGEvent? in
            let t = CGFloat(step) / CGFloat(steps)
            let p = CGPoint(x: point.x + (destination.x - point.x) * t,
                            y: point.y + (destination.y - point.y) * t)
            return CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                           mouseCursorPosition: p, mouseButton: .left)
        }
        guard events.count == steps else {
            completion(false)
            return
        }
        let originalPointer = ScreenGeometry.currentPointer()
        var lastPoint = point
        var finished = false
        isDragging = true
        let finish: (Bool) -> Void = { succeeded in
            guard !finished else { return }
            finished = true
            up.location = lastPoint
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            up.post(tap: .cghidEventTap)
            CGWarpMouseCursorPosition(originalPointer)
            self.isDragging = false
            completion(succeeded)
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)

        for (index, event) in events.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index + 1) * 0.02) {
                guard !finished else { return }
                guard self.isEnabled, AXIsProcessTrusted() else { finish(false); return }
                lastPoint = event.location
                event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
                event.post(tap: .cghidEventTap)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps + 1) * 0.02 + hold) {
            finish(self.isEnabled && AXIsProcessTrusted())
        }
    }

    private func titlebarCandidates(of window: AXUIElement) -> [CGPoint] {
        guard let frame = AccessibilityWindows.shared.frame(of: window) else { return [] }
        let buttons = [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute]
            .compactMap { attributeElement(window, $0 as CFString) }
            .compactMap { AccessibilityWindows.shared.frame(of: $0) }
        let xs = [frame.midX, frame.maxX - 32, (buttons.map(\.maxX).max() ?? frame.minX + 100) + 24]
            .filter { $0 > frame.minX + 8 && $0 < frame.maxX - 8 }
        let buttonYs = buttons.map(\.midY).filter { $0 > frame.minY && $0 < min(frame.maxY, frame.minY + 70) }
        // Browsers can expose hidden traffic lights above their actual window.
        let ys = Array(Set(buttonYs)).sorted() + [frame.minY + 6, frame.minY + 14, frame.minY + 24]
        return ys.filter { $0 < frame.maxY }.flatMap { y in xs.map { CGPoint(x: $0, y: y) } }
    }

    private func titlebarPoint(of window: AXUIElement) -> CGPoint? {
        let title = attributeElement(window, kAXTitleUIElementAttribute as CFString)
        let systemWide = AXUIElementCreateSystemWide()
        for point in titlebarCandidates(of: window) {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
                  let hit else { continue }
            if CFEqual(hit, window) || (title.map { CFEqual(hit, $0) } ?? false) { return point }
            if isTitlebarContainer(hit, of: window) { return point }
        }
        return nil
    }

    private func isTitlebarContainer(_ hit: AXUIElement, of window: AXUIElement) -> Bool {
        guard let windowFrame = AccessibilityWindows.shared.frame(of: window),
              let hitFrame = AccessibilityWindows.shared.frame(of: hit),
              let hitRole = attributeString(hit, kAXRoleAttribute as CFString),
              [kAXGroupRole, kAXToolbarRole].contains(hitRole),
              hitFrame.minY >= windowFrame.minY - 1, hitFrame.maxY <= windowFrame.minY + 70,
              hitFrame.height > 0, hitFrame.width > 100 else { return false }
        var node: AXUIElement? = hit
        let allowedRoles = [kAXGroupRole, kAXToolbarRole, kAXWindowRole]
        for _ in 0..<12 {
            guard let current = node else { return false }
            if CFEqual(current, window) { return true }
            guard let role = attributeString(current, kAXRoleAttribute as CFString), allowedRoles.contains(role) else {
                return false
            }
            node = attributeElement(current, kAXParentAttribute as CFString)
        }
        return false
    }

    private func attributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func onScreenWindowID(for window: AXUIElement) -> CGWindowID? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let frame = AccessibilityWindows.shared.frame(of: window),
              let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let matches = info.filter {
            guard ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = windowBounds($0) else { return false }
            return abs(bounds.minX - frame.minX) < 2 && abs(bounds.minY - frame.minY) < 2 &&
                abs(bounds.width - frame.width) < 2 && abs(bounds.height - frame.height) < 2
        }
        guard matches.count == 1 else { return nil }
        return (matches[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }

    private func attributeElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func windowBounds(_ window: [String: Any]) -> CGRect? {
        guard let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = number(rawBounds["X"]),
              let y = number(rawBounds["Y"]),
              let width = number(rawBounds["Width"]),
              let height = number(rawBounds["Height"])
        else { return nil }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? NSNumber { return CGFloat(value.doubleValue) }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        return nil
    }
}
