import Foundation

enum LoginItem {
    private static let label = "com.jafupy.fling"
    private static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: file.path) }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard let executable = Bundle.main.executableURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            let properties: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable.path, "--background"],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try configureService(enabled: true)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        } else {
            try configureService(enabled: false)
            if isEnabled { try FileManager.default.removeItem(at: file) }
        }
    }

    private static func configureService(enabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [enabled ? "enable" : "disable", "gui/\(getuid())/\(label)"]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "FlingLoginItem", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "Couldn’t update Open at login." : detail])
        }
    }
}
