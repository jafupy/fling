import AppKit
import ApplicationServices

final class WindowFrameHistory {
    private struct Entry {
        let window: AXUIElement
        let pid: pid_t
        var original: CGRect
        var applied: CGRect
        var zone: SnapZone?
        var sizeOffset = 0
    }

    private var entries: [Entry] = []

    func capture(_ frame: CGRect, of window: AXUIElement) {
        entries.removeAll { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated != false }
        if let index = index(of: window) {
            if !matches(frame, entries[index].applied) {
                entries[index].original = frame
            }
        } else {
            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success else { return }
            if entries.count == 64 { entries.removeFirst() }
            entries.append(Entry(window: window, pid: pid, original: frame, applied: frame))
        }
    }

    func didApply(_ frame: CGRect, to window: AXUIElement, zone: SnapZone, sizeOffset: Int) {
        guard let index = index(of: window) else { return }
        entries[index].applied = frame
        entries[index].zone = zone
        entries[index].sizeOffset = sizeOffset
    }

    func snapState(of window: AXUIElement, frame: CGRect?) -> (zone: SnapZone, sizeOffset: Int)? {
        guard let frame, let index = index(of: window),
              matches(frame, entries[index].applied), let zone = entries[index].zone else { return nil }
        return (zone, entries[index].sizeOffset)
    }

    func originalFrame(of window: AXUIElement) -> CGRect? {
        guard let index = index(of: window) else { return nil }
        return entries[index].original
    }

    func forget(_ window: AXUIElement) {
        entries.removeAll { CFEqual($0.window, window) }
    }

    private func index(of window: AXUIElement) -> Int? {
        entries.firstIndex { CFEqual($0.window, window) }
    }

    private func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 &&
            abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}
