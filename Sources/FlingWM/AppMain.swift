import AppKit
import ApplicationServices
import CMultitouchShim
import Combine
import Darwin

@main
enum FlingWMMain {
    static var showsSettingsOnLaunch: Bool {
        CommandLine.arguments.contains("--settings") ||
            (Bundle.main.bundleURL.pathExtension == "app" &&
             !CommandLine.arguments.contains("--background"))
    }

    static func main() {
        if CommandLine.arguments.contains("--enable-login-item") {
            do {
                try LoginItem.setEnabled(true)
                print("Open at login enabled.")
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        let lock = open(NSTemporaryDirectory() + "FlingWM.lock", O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else {
            FileHandle.standardError.write(Data("Couldn’t start Fling.\n".utf8))
            exit(1)
        }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if showsSettingsOnLaunch {
                DistributedNotificationCenter.default().postNotificationName(
                    AppDelegate.openSettingsNotification, object: nil, deliverImmediately: true)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static let openSettingsNotification = Notification.Name("com.jafupy.fling.openSettings")
    private let touchReader = MultitouchReader()
    private lazy var gestureEngine = GestureEngine()
    private let nativeGestures = NativeGestureReservation()
    @Published var enabled = true {
        didSet { if !enabled { gestureEngine.cancel() } }
    }
    @Published private(set) var reservesFourFingers = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibility()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings),
            name: Self.openSettingsNotification, object: nil)

        // Reserve the four-finger lane with a runtime event tap. No Trackpad
        // preferences are changed and Dock is never restarted.
        if nativeGestures.start() {
            reservesFourFingers = nativeGestures.isReserved
        } else {
            reservesFourFingers = false
            showAlert(
                title: "Could not reserve 4 fingers",
                message: "The gesture event tap could not be created. Grant Accessibility permission, quit FlingWM, then launch it again."
            )
        }

        touchReader.onFrame = { [weak self] frame in
            guard let self else { return }
            let shouldHandle = self.nativeGestures.update(frame)
            guard self.enabled else { return }
            if shouldHandle {
                self.gestureEngine.consume(frame)
            } else if frame.touches.count >= 4 {
                // A fourth finger added to an already-running native three-finger
                // gesture must not create a partial FlingWM session.
                self.gestureEngine.cancel()
            } else {
                self.gestureEngine.consume(frame)
            }
        }

        if !touchReader.start() {
            showAlert(
                title: "Trackpad unavailable",
                message: "FlingWM could not open MultitouchSupport.framework. This MVP uses Apple's private raw-trackpad framework."
            )
        }
        if FlingWMMain.showsSettingsOnLaunch { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchReader.stop()
        nativeGestures.stop()
    }

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func setReservesFourFingers(_ reserved: Bool) {
        if reserved { nativeGestures.reserve() }
        else { nativeGestures.restore() }
        reservesFourFingers = nativeGestures.isReserved
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.present()
    }

    func promptAccessibility() {
        requestAccessibility()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
