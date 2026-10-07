import Foundation

struct SettingsDraft {
    var edgeSizes: String
    var centerSizes: String
    var horizontalPadding: String
    var verticalPadding: String
    var windowGap: String
    var moveThreshold: Double
    var scaleThreshold: Double
    var hapticsEnabled: Bool

    init() {
        let values = SettingsStore.shared.editableValues()
        edgeSizes = values.edgeSizes
        centerSizes = values.centerSizes
        horizontalPadding = String(format: "%g", values.horizontalPadding)
        verticalPadding = String(format: "%g", values.verticalPadding)
        windowGap = String(format: "%g", values.windowGap)
        moveThreshold = values.moveThreshold
        scaleThreshold = values.scaleThreshold
        hapticsEnabled = values.hapticsEnabled
    }

    var spacing: (horizontal: Double, vertical: Double, gap: Double)? {
        guard let horizontal = Double(horizontalPadding), horizontal.isFinite,
              let vertical = Double(verticalPadding), vertical.isFinite,
              let gap = Double(windowGap), gap.isFinite else { return nil }
        return (horizontal, vertical, gap)
    }

    func save() -> String? {
        guard let spacing else { return "Enter a number for each padding and gap value." }
        return SettingsStore.shared.save(
            edgeSizes: edgeSizes,
            centerSizes: centerSizes,
            horizontalPadding: spacing.horizontal,
            verticalPadding: spacing.vertical,
            windowGap: spacing.gap,
            moveThreshold: moveThreshold,
            scaleThreshold: scaleThreshold,
            hapticsEnabled: hapticsEnabled
        )
    }
}
