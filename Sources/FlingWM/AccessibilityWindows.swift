import AppKit
import ApplicationServices

final class AccessibilityWindows {
    static let shared = AccessibilityWindows()
    private let systemWide = AXUIElementCreateSystemWide()

    private init() {}

    func window(at point: CGPoint) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard error == .success, let element else { return nil }

        if let window = attributeElement(element, kAXWindowAttribute as CFString) {
            return window
        }

        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { break }
            if role(of: node) == (kAXWindowRole as String) { return node }
            current = attributeElement(node, kAXParentAttribute as CFString)
        }

        return nil
    }

    func focusedWindow() -> AXUIElement? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return attributeElement(appElement, kAXFocusedWindowAttribute as CFString)
    }

    func frame(of window: AXUIElement) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let positionRef, let sizeRef,
            CFGetTypeID(positionRef) == AXValueGetTypeID(),
            CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        let positionValue = unsafeBitCast(positionRef, to: AXValue.self)
        let sizeValue = unsafeBitCast(sizeRef, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    func setFrame(_ frame: CGRect, of window: AXUIElement) {
        guard AXIsProcessTrusted() else { return }
        var position = frame.origin
        var size = frame.size
        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return }

        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid > 0 else { return }
        let app = AXUIElementCreateApplication(pid)
        let enhancedUI = "AXEnhancedUserInterface" as CFString
        var originalUI: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhancedUI, &originalUI) == .success &&
            (originalUI as? Bool) == true

        // Animated AX updates can restore an old position during a resize.
        if wasEnhanced {
            AXUIElementSetAttributeValue(app, enhancedUI, kCFBooleanFalse)
        }
        defer {
            // Zen can change this flag while returning an AX error.
            if wasEnhanced, let originalUI {
                AXUIElementSetAttributeValue(app, enhancedUI, originalUI)
            }
        }

        // Resize before moving, then reapply size for the destination display.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func attributeElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}
