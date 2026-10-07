import AppKit
import SwiftUI

struct SettingsPreview: View {
    let draft: SettingsDraft
    @State private var centered = false
    @State private var selectedSize: CGFloat = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sizes: [CGFloat] {
        SettingsStore.parsePercentList(centered ? draft.centerSizes : draft.edgeSizes) ?? []
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Position", selection: $centered) {
                    Text("Edge").tag(false)
                    Text("Centre").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("Size", selection: $selectedSize) {
                    ForEach(sizes, id: \.self) { size in
                        Text(size, format: .percent.precision(.fractionLength(0))).tag(size)
                    }
                }
                .frame(width: 110)
                .disabled(sizes.isEmpty)
            }

            if sizes.isEmpty {
                ContentUnavailableView("Enter valid window sizes", systemImage: "rectangle.dashed")
                    .frame(height: 120)
            } else {
                displayPreview
                    .frame(height: 120)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(centered ? "Centre" : "Left edge") at \(Int((selectedSize * 100).rounded())) percent")
            }
        }
        .padding(.vertical, 2)
        .onChange(of: centered) { _, _ in selectDefault() }
        .onChange(of: sizes) { _, values in
            if !values.contains(selectedSize) { selectDefault() }
        }
        .onAppear(perform: selectDefault)
    }

    private var displayPreview: some View {
        GeometryReader { geometry in
            let display = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            let scale = min(geometry.size.width / display.width, geometry.size.height / display.height)
            let screen = CGSize(width: display.width * scale, height: display.height * scale)
            let spacing = draft.spacing ?? (horizontal: 0, vertical: 0, gap: 0)
            let insetX = max(0, spacing.horizontal) * scale
            let insetY = max(0, spacing.vertical) * scale
            let useInsets = screen.width - insetX * 2 >= 160 * scale && screen.height - insetY * 2 >= 120 * scale
            let available = CGSize(
                width: screen.width - (useInsets ? insetX * 2 : 0),
                height: screen.height - (useInsets ? insetY * 2 : 0)
            )
            let width = centered
                ? min(available.width, max(180 * scale, available.width * selectedSize))
                : max(120 * scale, available.width * selectedSize - max(0, spacing.gap) * scale / 2)
            let height = centered ? min(available.height, max(120 * scale, available.height * selectedSize)) : available.height
            let gap = max(0, spacing.gap) * scale
            let neighbourWidth = max(0, available.width - width - gap)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                if !centered, neighbourWidth > 0 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.tint.opacity(0.22))
                        .frame(width: neighbourWidth, height: height)
                        .offset(x: (useInsets ? insetX : 0) + width + gap)
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(.tint)
                    .overlay {
                        Text(selectedSize, format: .percent.precision(.fractionLength(0)))
                            .font(.headline).foregroundStyle(.white)
                    }
                    .frame(width: width, height: height)
                    .offset(x: centered ? (screen.width - width) / 2 : useInsets ? insetX : 0)
            }
            .frame(width: screen.width, height: screen.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selectedSize)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: centered)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: draft.horizontalPadding)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: draft.verticalPadding)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: draft.windowGap)
    }

    private func selectDefault() {
        let preferred: CGFloat = centered ? 0.6 : 0.5
        selectedSize = sizes.min(by: { abs($0 - preferred) < abs($1 - preferred) }) ?? preferred
    }
}
