import Foundation
import CoreGraphics
import CMultitouchShim

/// Owns macOS' four-finger gesture lane at runtime without rewriting Trackpad
/// preferences. It deliberately refuses to steal a gesture that has already
/// committed as a native three-finger swipe before a fourth finger is added.
final class NativeGestureReservation {
    private(set) var isReserved = false

    private var contactSequenceActive = false
    private var ownsCurrentSequence = false
    private var rejectCurrentSequence = false

    private var threeFingerEnteredAt: Double?
    private var threeFingerOrigin: CGPoint?
    private var threeFingerMaxTravel: Double = 0

    private var releaseWorkItem: DispatchWorkItem?

    private let lateFourthMovementThreshold = 0.030
    private let lateFourthTimeThreshold = 0.32

    @discardableResult
    func start() -> Bool {
        guard FWMGestureBlockerStart() else { return false }
        FWMGestureBlockerSetEnabled(true)
        isReserved = true
        return true
    }

    func stop() {
        endOwnershipImmediately()
        resetSequence()
        isReserved = false
        FWMGestureBlockerSetEnabled(false)
        FWMGestureBlockerStop()
    }

    func reserve() {
        if !FWMGestureBlockerIsRunning() {
            guard FWMGestureBlockerStart() else {
                isReserved = false
                return
            }
        }
        isReserved = true
        FWMGestureBlockerSetEnabled(true)
    }

    func restore() {
        endOwnershipImmediately()
        resetSequence()
        isReserved = false
        FWMGestureBlockerSetEnabled(false)
    }

    func restoreSynchronously() {
        restore()
        FWMGestureBlockerStop()
    }

    /// Returns true only when this frame belongs to a four-finger sequence that
    /// FlingWM should handle. A fourth finger added after a three-finger desktop
    /// swipe has visibly started is rejected for the rest of that touch sequence.
    @discardableResult
    func update(_ frame: TouchFrame) -> Bool {
        let count = frame.touches.count

        if count == 0 {
            if ownsCurrentSequence { releaseOwnershipAfterTail() }
            resetSequence(keepOwnershipTail: true)
            return false
        }

        if !contactSequenceActive {
            contactSequenceActive = true
            ownsCurrentSequence = false
            rejectCurrentSequence = false
            threeFingerEnteredAt = nil
            threeFingerOrigin = nil
            threeFingerMaxTravel = 0
        }

        if count == 3, !ownsCurrentSequence, !rejectCurrentSequence {
            let c = centroid(frame.touches)
            if threeFingerEnteredAt == nil {
                threeFingerEnteredAt = frame.timestamp
                threeFingerOrigin = c
            }
            if let origin = threeFingerOrigin {
                threeFingerMaxTravel = max(
                    threeFingerMaxTravel,
                    hypot(Double(c.x - origin.x), Double(c.y - origin.y))
                )
            }
            return false
        }

        if count >= 4 {
            if !ownsCurrentSequence, !rejectCurrentSequence {
                let spentAsThree = threeFingerEnteredAt.map { frame.timestamp - $0 } ?? 0
                let looksLikeExistingThreeFingerGesture =
                    threeFingerMaxTravel >= lateFourthMovementThreshold ||
                    spentAsThree >= lateFourthTimeThreshold

                if looksLikeExistingThreeFingerGesture {
                    // Do not suddenly suppress Mission Control/Spaces halfway
                    // through an already-moving three-finger gesture.
                    rejectCurrentSequence = true
                    return false
                }

                ownsCurrentSequence = true
                releaseWorkItem?.cancel()
                releaseWorkItem = nil
                if isReserved {
                    FWMGestureBlockerSetFourFingerActive(true)
                }
            }

            return ownsCurrentSequence && !rejectCurrentSequence && count == 4
        }

        // If an owned four-finger gesture is lifting through 3/2/1 contacts,
        // retain the blocker briefly so the terminal Dock event cannot leak.
        if ownsCurrentSequence {
            releaseOwnershipAfterTail()
        }
        return false
    }

    private func centroid(_ touches: [TouchPoint]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        return CGPoint(
            x: touches.map(\.x).reduce(0, +) / Double(touches.count),
            y: touches.map(\.y).reduce(0, +) / Double(touches.count)
        )
    }

    private func releaseOwnershipAfterTail() {
        releaseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            FWMGestureBlockerSetFourFingerActive(false)
            self.releaseWorkItem = nil
        }
        releaseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: item)
    }

    private func endOwnershipImmediately() {
        releaseWorkItem?.cancel()
        releaseWorkItem = nil
        FWMGestureBlockerSetFourFingerActive(false)
    }

    private func resetSequence(keepOwnershipTail: Bool = false) {
        contactSequenceActive = false
        ownsCurrentSequence = false
        rejectCurrentSequence = false
        threeFingerEnteredAt = nil
        threeFingerOrigin = nil
        threeFingerMaxTravel = 0
        if !keepOwnershipTail {
            endOwnershipImmediately()
        }
    }
}
