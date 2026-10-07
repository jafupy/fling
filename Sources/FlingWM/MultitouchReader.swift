import Foundation
import Darwin
import CMultitouchShim

struct TouchPoint {
    let id: Int32
    let x: Double
    let y: Double
    let state: UInt32
}

struct TouchFrame {
    let timestamp: Double
    let touches: [TouchPoint]
}

private typealias MTFrameCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<MTTouch>?,
    Int,
    Double,
    Int
) -> Void

private typealias MTDeviceCreateDefaultFn = @convention(c) () -> UnsafeMutableRawPointer?
private typealias MTRegisterContactFrameCallbackFn = @convention(c) (UnsafeMutableRawPointer?, MTFrameCallback?) -> Void
private typealias MTDeviceStartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
private typealias MTDeviceStopFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias MTDeviceReleaseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

private var activeReader: MultitouchReader?

private let frameCallback: MTFrameCallback = { _, touchPointer, count, timestamp, _ in
    guard count >= 0, count == 0 || touchPointer != nil else { return }

    var points: [TouchPoint] = []
    points.reserveCapacity(count)

    if let touchPointer {
        for index in 0..<count {
            let touch = touchPointer[index]
            // 3 = make touch, 4 = touching. Other states are transition/hover states.
            guard touch.state == 3 || touch.state == 4 else { continue }
            points.append(
                TouchPoint(
                    id: touch.pathIndex,
                    x: Double(touch.normalizedVector.position.x),
                    y: Double(touch.normalizedVector.position.y),
                    state: touch.state
                )
            )
        }
    }

    let frame = TouchFrame(timestamp: timestamp, touches: points)
    DispatchQueue.main.async {
        activeReader?.onFrame?(frame)
    }
}

final class MultitouchReader {
    var onFrame: ((TouchFrame) -> Void)?

    private var library: UnsafeMutableRawPointer?
    private var device: UnsafeMutableRawPointer?
    private var stopFn: MTDeviceStopFn?
    private var releaseFn: MTDeviceReleaseFn?

    func start() -> Bool {
        guard library == nil else { return true }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let library = dlopen(path, RTLD_NOW) else { return false }
        self.library = library

        guard
            let createDefault: MTDeviceCreateDefaultFn = symbol("MTDeviceCreateDefault", in: library),
            let register: MTRegisterContactFrameCallbackFn = symbol("MTRegisterContactFrameCallback", in: library),
            let start: MTDeviceStartFn = symbol("MTDeviceStart", in: library),
            let stopDevice: MTDeviceStopFn = symbol("MTDeviceStop", in: library),
            let releaseDevice: MTDeviceReleaseFn = symbol("MTDeviceRelease", in: library),
            let device = createDefault()
        else {
            cleanupLibrary()
            return false
        }

        self.device = device
        self.stopFn = stopDevice
        self.releaseFn = releaseDevice
        activeReader = self

        register(device, frameCallback)
        let result = start(device, 0)
        if result != 0 {
            self.stop()
            return false
        }

        return true
    }

    func stop() {
        if let device {
            _ = stopFn?(device)
            releaseFn?(device)
        }
        device = nil
        stopFn = nil
        releaseFn = nil
        if activeReader === self { activeReader = nil }
        cleanupLibrary()
    }

    deinit {
        stop()
    }

    private func cleanupLibrary() {
        if let library { dlclose(library) }
        library = nil
    }

    private func symbol<T>(_ name: String, in library: UnsafeMutableRawPointer) -> T? {
        guard let raw = dlsym(library, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
