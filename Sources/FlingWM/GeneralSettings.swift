import AppKit
import SwiftUI

struct GeneralSettings: View {
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var error: String?

    var body: some View {
        if let delegate = NSApp.delegate as? AppDelegate {
            FlingControls(delegate: delegate)
        }
        Section {
            Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                .toggleStyle(.switch)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Startup")
        } footer: {
            Text("Start Fling automatically when you sign in to your Mac. This setting applies immediately.")
        }
        .onAppear { openAtLogin = LoginItem.isEnabled }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            openAtLogin = LoginItem.isEnabled
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        openAtLogin = LoginItem.isEnabled
    }
}

private struct FlingControls: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        Section("Fling") {
            Toggle("Enabled", isOn: $delegate.enabled)
                .toggleStyle(.switch)
            Toggle("Reserve four-finger gestures", isOn: Binding(
                get: { delegate.reservesFourFingers }, set: delegate.setReservesFourFingers))
                .toggleStyle(.switch)
            HStack {
                Button("Request Accessibility Permission", action: delegate.promptAccessibility)
                Spacer()
                Button("Quit Fling") { NSApp.terminate(nil) }
            }
        }
    }
}
