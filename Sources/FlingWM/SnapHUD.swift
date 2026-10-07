import AppKit
import QuartzCore

final class SnapHUD {
    enum Presentation {
        case snap
        case restored
        case sendToSidebar
    }

    static let shared = SnapHUD()
    private var panel: NSPanel?

    private init() {}

    func show(quartzFrame: CGRect, label: String, presentation: Presentation = .snap) {
        guard !quartzFrame.isEmpty, !quartzFrame.isInfinite, !quartzFrame.isNull else {
            hide()
            return
        }
        let cocoaFrame = ScreenGeometry.quartzToCocoa(quartzFrame)
        let panel: NSPanel

        // Commit the resized surface and its outline together. Otherwise the
        // window can grow before Core Animation presents its new layer bounds.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let existing = self.panel {
            panel = existing
            panel.setFrame(cocoaFrame, display: false)
        } else {
            panel = NSPanel(
                contentRect: cocoaFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.isOpaque = false
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = HUDView(frame: panel.contentView?.bounds ?? .zero)
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            self.panel = panel
        }

        if let view = panel.contentView as? HUDView {
            view.update(label: label, presentation: presentation)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            view.needsDisplay = true
        }
        panel.displayIfNeeded()
        CATransaction.commit()
        CATransaction.flush()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.close()
        panel = nil
    }
}

private final class HUDView: NSView {
    private let outline = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        outline.actions = ["bounds": NSNull(), "position": NSNull(), "path": NSNull()]
        outline.lineWidth = 3
        layer?.addSublayer(outline)
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func update(label text: String, presentation: SnapHUD.Presentation) {
        label.stringValue = text
        let color: NSColor = presentation == .sendToSidebar ? .systemOrange : .controlAccentColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.fillColor = color.withAlphaComponent(0.12).cgColor
        outline.strokeColor = color.withAlphaComponent(0.9).cgColor
        outline.lineDashPattern = presentation == .sendToSidebar ? [8, 6] : nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.frame = bounds
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), cornerWidth: 18, cornerHeight: 18, transform: nil)
        CATransaction.commit()
        label.sizeToFit()
        label.frame = CGRect(x: 20, y: bounds.midY - label.frame.height / 2,
                             width: max(0, bounds.width - 40), height: label.frame.height)
    }
}
