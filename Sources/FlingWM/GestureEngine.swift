import AppKit
import ApplicationServices

private enum GestureTarget {
    case window(AXUIElement)
    case stagePreview(point: CGPoint)
}

private struct GestureSession {
    let id = UUID()
    let pointerAtStart: CGPoint
    let initialSpread: Double

    var target: GestureTarget?
    var originalFrame: CGRect?
    var capturedRestoreFrame = false
    var scrub = ScrubGesture()
    var removal = PinchRemovalGesture()
    var canSendToSidebar: Bool?
    var restored = false

    // Position and scale are independent channels. Either can happen first and
    // both can keep changing until lift-off.
    var zone: SnapZone?
    var position: FlingPosition
    var fullBoundaryDirection: Int?
    var fullBoundaryAxis: FlingPosition.Axis?
    var positionIntentActive = false
    var correctingPosition = false
    var sizeOffset = 0

    // Advance the scale baseline by accepted notches, keeping any extra motion
    // from a fast pinch available for the next step or removal.
    var scaleAnchorSpread: Double
    var scaleAnchorRadii: [Int32: Double]
    var pendingScaleDirection = 0
    var pendingScaleFrames = 0

    var stageActivationStarted = false
    var stageReady = false

    var lastAppliedZone: SnapZone?
    var lastAppliedOffset: Int?
    var appliedRevision = 0
}

final class GestureEngine {
    private let scaleConfirmationFrames = 2

    private var session: GestureSession?
    private var fourFingerFrames = 0
    private let history = WindowFrameHistory()
    private var ignoreUntilLift = false
    private var stageRemovalInProgress = false

    func consume(_ frame: TouchFrame) {
        let touches = frame.touches

        if ignoreUntilLift || stageRemovalInProgress {
            if touches.isEmpty { ignoreUntilLift = false }
            else if stageRemovalInProgress { ignoreUntilLift = true }
            return
        }

        guard touches.count == 4 else {
            // Removal commits on full lift, not a transient missing contact.
            if touches.isEmpty { finish() }
            else if touches.count > 4 { cancel(); ignoreUntilLift = true }
            fourFingerFrames = 0
            return
        }

        fourFingerFrames += 1
        let centroid = centroid(of: touches)
        let radii = radiiByFinger(of: touches, around: centroid)
        guard radii.count == 4 else {
            cancel()
            return
        }
        let spread = meanRadius(radii)

        if session == nil {
            // Avoid treating the final 1->2->3->4 landing transition as motion.
            guard fourFingerFrames >= 2 else { return }

            let pointer = ScreenGeometry.currentPointer()
            let target = resolveTarget(at: pointer)
            let originalFrame: CGRect?
            if case let .window(window)? = target {
                originalFrame = AccessibilityWindows.shared.frame(of: window)
            } else {
                originalFrame = nil
            }

            var inferred = SnapLayout.inferInitialState(frame: originalFrame, pointer: pointer)
            var correctingPosition = false
            if case let .window(window)? = target,
               let remembered = history.snapState(of: window, frame: originalFrame) {
                inferred = (remembered.zone, remembered.sizeOffset)
                correctingPosition = true
            }

            var initial = GestureSession(
                pointerAtStart: pointer,
                initialSpread: max(spread, 0.0001),
                target: target,
                originalFrame: originalFrame,
                zone: inferred.zone,
                position: FlingPosition(origin: centroid),
                correctingPosition: correctingPosition,
                sizeOffset: inferred.sizeOffset,
                scaleAnchorSpread: max(spread, 0.0001),
                scaleAnchorRadii: radii,
                stageReady: {
                    if case .window? = target { return true }
                    return false
                }()
            )
            let settings = SettingsStore.shared.snapshot()
            clampSizeOffset(&initial, for: initial.zone, settings: settings)
            if let zone = initial.zone, zone != .full,
               initial.sizeOffset == offsetRange(for: zone, settings: settings).lowerBound {
                initial.removal.reset(radii: radii)
            }
            session = initial
            return
        }

        guard var s = session else { return }
        guard Set(radii.keys) == Set(s.scaleAnchorRadii.keys) else {
            cancel()
            ignoreUntilLift = true
            return
        }
        guard !s.restored else { return }
        let settings = SettingsStore.shared.snapshot()

        if s.scrub.update(centroid: centroid, timestamp: frame.timestamp,
                          distance: max(0.04, min(0.07, settings.moveThreshold * 0.6)),
                          spreadRatio: spread / s.initialSpread),
           s.stageReady, case let .window(window)? = s.target {
            if let original = history.originalFrame(of: window) {
                AccessibilityWindows.shared.setFrame(original, of: window)
                if let actual = AccessibilityWindows.shared.frame(of: window) {
                    let restored = SnapLayout.frameError(actual, original) < 2
                    if restored { history.forget(window); haptic(settings) }
                    SnapHUD.shared.show(quartzFrame: actual,
                        label: restored ? "Restored" : "Couldn’t restore",
                        presentation: .restored)
                }
            } else {
                SnapHUD.shared.hide()
            }
            s.restored = true
            s.removal.reset()
            session = s
            return
        }

        if let zone = s.zone, zone != .full,
           s.sizeOffset == offsetRange(for: zone, settings: settings).lowerBound,
           s.stageReady, case let .window(window)? = s.target {
            if s.canSendToSidebar == nil {
                s.canSendToSidebar = StageManager.shared.canRemoveWindowFromCurrentSet(window)
            }
            if s.canSendToSidebar == true, StageManager.shared.isEnabled {
                let wasArmed = s.removal.isArmed
                s.removal.update(radii: radii)
                if wasArmed != s.removal.isArmed {
                    if settings.hapticsEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    }
                    s.scaleAnchorSpread = max(spread, 0.0001)
                    s.scaleAnchorRadii = radii
                    s.pendingScaleDirection = 0
                    s.pendingScaleFrames = 0
                    if let actual = AccessibilityWindows.shared.frame(of: window) {
                        SnapHUD.shared.show(quartzFrame: actual,
                            label: s.removal.isArmed ? "Send to sidebar · Lift to send" : "Cancelled",
                            presentation: s.removal.isArmed ? .sendToSidebar : .snap)
                    }
                }
                if s.removal.isArmed { session = s; return }
            } else {
                s.removal.reset()
            }
        } else {
            s.removal.reset()
        }

        var changed = false

        if let movement = s.position.update(at: centroid, timestamp: frame.timestamp, threshold: settings.moveThreshold) {
            let firstMove = !s.positionIntentActive
            s.correctingPosition = s.correctingPosition || (!firstMove && movement.beginsStroke)
            let next: (zone: SnapZone, offset: Int)
            if s.correctingPosition {
                next = FlingPosition.destination(zone: s.zone, offset: s.sizeOffset, movement: movement,
                    fullBoundaryDirection: s.fullBoundaryAxis == movement.axis ? s.fullBoundaryDirection : nil,
                    settings: settings)
            } else {
                let zone: SnapZone = movement.axis == .horizontal
                    ? (movement.direction < 0 ? .left : .right)
                    : (movement.direction > 0 ? .top : .bottom)
                next = (zone, firstMove || zone != s.zone ? 0 : s.sizeOffset)
                // The initial stroke picks an edge, regardless of its length.
                s.position.reanchor(at: centroid)
            }
            s.fullBoundaryDirection = next.zone == .full
                ? (movement.axis == .horizontal ? movement.direction : -movement.direction) : nil
            s.fullBoundaryAxis = next.zone == .full ? movement.axis : nil
            s.positionIntentActive = true
            if firstMove || next.zone != s.zone || next.offset != s.sizeOffset {
                s.zone = next.zone
                s.sizeOffset = next.offset
                clampSizeOffset(&s, for: next.zone, settings: settings)
                s.removal.reset()
                if s.sizeOffset == offsetRange(for: next.zone, settings: settings).lowerBound,
                   next.zone != .full {
                    s.removal.reset(radii: radii)
                }
                changed = true
                haptic(settings)
            }
        }

        // SCALE CHANNEL ------------------------------------------------------
        // Translation is removed by measuring finger radii around the current
        // centroid. Requiring 3/4 fingers to agree radially avoids most accidental
        // size changes during a fling.
        let spreadDelta = (spread / max(s.scaleAnchorSpread, 0.0001)) - 1.0
        let scaleNotches = ScaleGesture.notches(
            radii: radii,
            anchor: s.scaleAnchorRadii,
            aggregateDelta: spreadDelta,
            threshold: settings.scaleThreshold
        )
        let scaleDirection = scaleNotches == 0 ? 0 : scaleNotches > 0 ? 1 : -1

        if scaleDirection == 0 {
            s.pendingScaleDirection = 0
            s.pendingScaleFrames = 0
        } else {
            if scaleDirection == s.pendingScaleDirection {
                s.pendingScaleFrames += 1
            } else {
                s.pendingScaleDirection = scaleDirection
                s.pendingScaleFrames = 1
            }

            if s.pendingScaleFrames >= scaleConfirmationFrames {
                if s.zone == nil {
                    s.zone = .center
                }

                var accepted = 0
                for _ in 0..<abs(scaleNotches) {
                    guard stepSize(direction: scaleDirection, session: &s, settings: settings) else { break }
                    accepted += 1
                }
                if accepted > 0 {
                    let factor = scaleDirection > 0 ? 1 + settings.scaleThreshold : 1 - settings.scaleThreshold
                    let advance = pow(factor, Double(accepted))
                    s.scaleAnchorSpread *= advance
                    s.scaleAnchorRadii = s.scaleAnchorRadii.mapValues { $0 * advance }
                    s.fullBoundaryDirection = nil
                    s.fullBoundaryAxis = nil
                    changed = true
                    haptic(settings)
                    if let zone = s.zone, zone != .full,
                       s.sizeOffset == offsetRange(for: zone, settings: settings).lowerBound {
                        // Keep excess contraction after reaching the minimum;
                        // a fast deep pinch must not lose its removal intent.
                        s.removal.reset(radii: s.scaleAnchorRadii)
                        s.removal.update(radii: radii)
                    }
                } else if scaleDirection > 0 || s.zone == .full || !StageManager.shared.isEnabled {
                    s.scaleAnchorSpread = max(spread, 0.0001)
                    s.scaleAnchorRadii = radii
                }

                // Advance only by the notches actually used. Resetting to the
                // latest hand span discarded steps during a fast pinch.
                s.pendingScaleDirection = 0
                s.pendingScaleFrames = 0
            }
        }

        // A Stage Manager preview must first be dragged into the current stage
        // group. Do that once we know the user actually meant to manipulate it.
        if (s.positionIntentActive || changed), case .stagePreview? = s.target {
            activateStagePreviewIfNeeded(&s)
        }

        session = s

        if changed {
            applyCurrentStateIfReady(sessionID: s.id)
        }
    }

    func cancel() {
        session = nil
        fourFingerFrames = 0
        ignoreUntilLift = false
        SnapHUD.shared.hide()
    }

    private func finish() {
        let completed = session
        session = nil
        SnapHUD.shared.hide()
        guard let completed, completed.removal.isArmed,
              case let .window(window)? = completed.target else { return }
        stageRemovalInProgress = true
        // Let the outline disappear and the final resize settle before AX hit
        // testing the title bar and matching its WindowServer frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            StageManager.shared.removeWindowFromCurrentSet(window) { [weak self] succeeded in
                guard let self else { return }
                self.stageRemovalInProgress = false
                if !succeeded, let actual = AccessibilityWindows.shared.frame(of: window) {
                    SnapHUD.shared.show(quartzFrame: actual, label: "Couldn’t send to sidebar")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        if self?.session == nil { SnapHUD.shared.hide() }
                    }
                }
            }
        }
    }

    private func centroid(of touches: [TouchPoint]) -> CGPoint {
        CGPoint(
            x: touches.map(\.x).reduce(0, +) / Double(touches.count),
            y: touches.map(\.y).reduce(0, +) / Double(touches.count)
        )
    }

    private func radiiByFinger(of touches: [TouchPoint], around centroid: CGPoint) -> [Int32: Double] {
        Dictionary(touches.map { touch in
            let radius = hypot(touch.x - Double(centroid.x), touch.y - Double(centroid.y))
            return (touch.id, radius)
        }, uniquingKeysWith: { first, _ in first })
    }

    private func meanRadius(_ radii: [Int32: Double]) -> Double {
        guard !radii.isEmpty else { return 0 }
        return radii.values.reduce(0, +) / Double(radii.count)
    }

    private func stepSize(direction: Int, session s: inout GestureSession, settings: FlingSettings) -> Bool {
        guard let zone = s.zone else { return false }
        if zone == .full {
            guard direction < 0 else { return false }
            s.zone = .center
            s.sizeOffset = settings.centerSizes.count - 1 - settings.centerDefaultIndex
            return true
        }
        let range = offsetRange(for: zone, settings: settings)
        if zone == .center, direction > 0, s.sizeOffset == range.upperBound {
            s.zone = .full
            s.sizeOffset = 0
            return true
        }
        let next = max(range.lowerBound, min(range.upperBound, s.sizeOffset + direction))
        guard next != s.sizeOffset else { return false }
        s.sizeOffset = next
        return true
    }

    private func clampSizeOffset(_ s: inout GestureSession, for zone: SnapZone?, settings: FlingSettings) {
        guard let zone else { return }
        let range = offsetRange(for: zone, settings: settings)
        s.sizeOffset = max(range.lowerBound, min(range.upperBound, s.sizeOffset))
    }

    private func offsetRange(for zone: SnapZone, settings: FlingSettings) -> ClosedRange<Int> {
        if zone == .full { return 0...0 }
        if zone.isEdge {
            let base = settings.edgeDefaultIndex
            return (-base)...(settings.edgeSizes.count - 1 - base)
        }
        let base = settings.centerDefaultIndex
        return (-base)...(settings.centerSizes.count - 1 - base)
    }

    private func currentSize(for zone: SnapZone, offset: Int, settings: FlingSettings) -> CGFloat {
        if zone == .full { return 1 }
        let values = zone.isEdge ? settings.edgeSizes : settings.centerSizes
        let base = zone.isEdge ? settings.edgeDefaultIndex : settings.centerDefaultIndex
        let index = max(0, min(values.count - 1, base + offset))
        return values[index]
    }

    private func resolveTarget(at point: CGPoint) -> GestureTarget? {
        if StageManager.shared.preview(at: point) != nil {
            return .stagePreview(point: point)
        }
        if let window = AccessibilityWindows.shared.window(at: point) {
            return .window(window)
        }
        return nil
    }

    private func activateStagePreviewIfNeeded(_ s: inout GestureSession) {
        guard case let .stagePreview(point)? = s.target, !s.stageActivationStarted else { return }
        s.stageActivationStarted = true
        let sessionID = s.id

        StageManager.shared.addPreviewToCurrentSet(at: point) { [weak self] succeeded in
            guard let self, var live = self.session, live.id == sessionID else { return }
            guard succeeded else {
                self.cancel()
                self.ignoreUntilLift = true
                return
            }

            if let window = AccessibilityWindows.shared.focusedWindow() {
                live.target = .window(window)
                live.originalFrame = AccessibilityWindows.shared.frame(of: window)
                live.stageReady = true
                self.session = live
                self.applyCurrentStateIfReady(sessionID: sessionID, force: true)
            }
        }
    }

    private func applyCurrentStateIfReady(sessionID: UUID, force: Bool = false) {
        guard var s = session, s.id == sessionID, s.stageReady else { return }
        guard let zone = s.zone else { return }
        guard case let .window(window)? = s.target else { return }
        guard let screen = ScreenGeometry.screenContaining(quartzPoint: s.pointerAtStart) else { return }

        let settings = SettingsStore.shared.snapshot()
        let available = SnapLayout.padded(screen.availableFrame, settings: settings)
        let size = currentSize(for: zone, offset: s.sizeOffset, settings: settings)
        let signatureChanged = force || s.lastAppliedZone != zone || s.lastAppliedOffset != s.sizeOffset
        guard signatureChanged else { return }

        let frame = SnapLayout.frameFor(zone: zone, size: size, in: available, gap: settings.windowGap)
        if !s.capturedRestoreFrame, let original = s.originalFrame {
            history.capture(original, of: window)
            s.capturedRestoreFrame = true
        }
        AccessibilityWindows.shared.setFrame(frame, of: window)
        if let actual = AccessibilityWindows.shared.frame(of: window) {
            history.didApply(actual, to: window, zone: zone, sizeOffset: s.sizeOffset)
            SnapHUD.shared.show(quartzFrame: actual, label: SnapLayout.labelFor(zone: zone, size: size))
        } else {
            SnapHUD.shared.hide()
        }

        s.appliedRevision += 1
        s.lastAppliedZone = zone
        s.lastAppliedOffset = s.sizeOffset
        session = s
        let revision = s.appliedRevision
        let label = SnapLayout.labelFor(zone: zone, size: size)
        // Some apps finish an AX resize after returning. Follow the settled
        // frame without keeping an observer or timer alive between gestures.
        for delay in [0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let live = self.session, live.id == sessionID,
                      live.appliedRevision == revision, !live.restored, !live.removal.isArmed,
                      let actual = AccessibilityWindows.shared.frame(of: window) else { return }
                self.history.didApply(actual, to: window, zone: zone, sizeOffset: live.sizeOffset)
                SnapHUD.shared.show(quartzFrame: actual, label: label)
            }
        }
    }

    private func haptic(_ settings: FlingSettings) {
        guard settings.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

}
