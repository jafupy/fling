import Foundation
import CoreGraphics

struct FlingSettings {
    let edgeSizes: [CGFloat]
    let centerSizes: [CGFloat]
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let windowGap: CGFloat
    let moveThreshold: Double
    let scaleThreshold: Double
    let hapticsEnabled: Bool

    var edgeDefaultIndex: Int { nearestIndex(in: edgeSizes, to: 0.50) }
    var centerDefaultIndex: Int { nearestIndex(in: centerSizes, to: 0.60) }

    private func nearestIndex(in values: [CGFloat], to target: CGFloat) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.enumerated().min(by: { abs($0.element - target) < abs($1.element - target) })?.offset ?? 0
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    static let changedNotification = Notification.Name("FlingWMSettingsChanged")

    private enum Key {
        static let edgeSizes = "edgeSizes"
        static let centerSizes = "centerSizes"
        static let horizontalPadding = "horizontalPadding"
        static let verticalPadding = "verticalPadding"
        static let windowGap = "windowGap"
        static let moveThreshold = "moveThreshold"
        static let scaleThreshold = "scaleThreshold"
        static let hapticsEnabled = "hapticsEnabled"
    }

    private let defaults = UserDefaults.standard

    private init() {
        if Bundle.main.bundleIdentifier == "com.jafupy.fling",
           !defaults.bool(forKey: "migratedLegacySettings") {
            let legacy = defaults.persistentDomain(forName: "FlingWM") ?? [:]
            let current = defaults.persistentDomain(forName: "com.jafupy.fling") ?? [:]
            for key in [Key.edgeSizes, Key.centerSizes, Key.horizontalPadding, Key.verticalPadding,
                        Key.windowGap, Key.moveThreshold, Key.scaleThreshold, Key.hapticsEnabled] {
                if current[key] == nil, let value = legacy[key] { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedLegacySettings")
        }
        defaults.register(defaults: [
            Key.edgeSizes: "33.333, 50, 66.667",
            Key.centerSizes: "40, 50, 60, 70, 80, 90",
            Key.horizontalPadding: 0.0,
            Key.verticalPadding: 0.0,
            Key.windowGap: 0.0,
            Key.moveThreshold: 8.5,
            Key.scaleThreshold: 6.5,
            Key.hapticsEnabled: true,
        ])
    }

    func snapshot() -> FlingSettings {
        FlingSettings(
            edgeSizes: Self.parsePercentList(defaults.string(forKey: Key.edgeSizes) ?? "") ?? [1.0 / 3.0, 0.5, 2.0 / 3.0],
            centerSizes: Self.parsePercentList(defaults.string(forKey: Key.centerSizes) ?? "") ?? [0.4, 0.5, 0.6, 0.7, 0.8, 0.9],
            horizontalPadding: CGFloat(max(0, defaults.double(forKey: Key.horizontalPadding))),
            verticalPadding: CGFloat(max(0, defaults.double(forKey: Key.verticalPadding))),
            windowGap: CGFloat(max(0, defaults.double(forKey: Key.windowGap))),
            moveThreshold: max(0.02, min(0.30, defaults.double(forKey: Key.moveThreshold) / 100.0)),
            scaleThreshold: max(0.02, min(0.30, defaults.double(forKey: Key.scaleThreshold) / 100.0)),
            hapticsEnabled: defaults.bool(forKey: Key.hapticsEnabled)
        )
    }

    func editableValues() -> (edgeSizes: String, centerSizes: String, horizontalPadding: Double, verticalPadding: Double, windowGap: Double, moveThreshold: Double, scaleThreshold: Double, hapticsEnabled: Bool) {
        (
            defaults.string(forKey: Key.edgeSizes) ?? "33.333, 50, 66.667",
            defaults.string(forKey: Key.centerSizes) ?? "40, 50, 60, 70, 80, 90",
            defaults.double(forKey: Key.horizontalPadding),
            defaults.double(forKey: Key.verticalPadding),
            defaults.double(forKey: Key.windowGap),
            defaults.double(forKey: Key.moveThreshold),
            defaults.double(forKey: Key.scaleThreshold),
            defaults.bool(forKey: Key.hapticsEnabled)
        )
    }

    @discardableResult
    func save(
        edgeSizes: String,
        centerSizes: String,
        horizontalPadding: Double,
        verticalPadding: Double,
        windowGap: Double,
        moveThreshold: Double,
        scaleThreshold: Double,
        hapticsEnabled: Bool
    ) -> String? {
        guard let parsedEdges = Self.parsePercentList(edgeSizes), !parsedEdges.isEmpty else {
            return "Edge sizes must be comma-separated percentages between 10 and 100."
        }
        guard let parsedCenters = Self.parsePercentList(centerSizes), !parsedCenters.isEmpty else {
            return "Centre sizes must be comma-separated percentages between 10 and 100."
        }
        guard horizontalPadding >= 0, verticalPadding >= 0, windowGap >= 0 else {
            return "Padding and gap cannot be negative."
        }
        guard (2...30).contains(moveThreshold), (2...30).contains(scaleThreshold) else {
            return "Gesture thresholds must be between 2% and 30%."
        }

        defaults.set(Self.formatPercentList(parsedEdges), forKey: Key.edgeSizes)
        defaults.set(Self.formatPercentList(parsedCenters), forKey: Key.centerSizes)
        defaults.set(horizontalPadding, forKey: Key.horizontalPadding)
        defaults.set(verticalPadding, forKey: Key.verticalPadding)
        defaults.set(windowGap, forKey: Key.windowGap)
        defaults.set(moveThreshold, forKey: Key.moveThreshold)
        defaults.set(scaleThreshold, forKey: Key.scaleThreshold)
        defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled)
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        return nil
    }

    func reset() {
        for key in [
            Key.edgeSizes,
            Key.centerSizes,
            Key.horizontalPadding,
            Key.verticalPadding,
            Key.windowGap,
            Key.moveThreshold,
            Key.scaleThreshold,
            Key.hapticsEnabled,
        ] {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    static func parsePercentList(_ text: String) -> [CGFloat]? {
        let parts = text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let values = parts.compactMap(Double.init)

        guard !values.isEmpty, values.count == parts.count, values.count <= 12 else { return nil }
        guard values.allSatisfy({ $0 >= 10 && $0 <= 100 }) else { return nil }

        let unique = Array(Set(values)).sorted()
        return unique.map { CGFloat($0 / 100.0) }
    }

    private static func formatPercentList(_ values: [CGFloat]) -> String {
        values.map { value in
            let percent = Double(value * 100)
            if abs(percent.rounded() - percent) < 0.005 {
                return String(Int(percent.rounded()))
            }
            return String(format: "%.3f", percent)
        }.joined(separator: ", ")
    }
}
