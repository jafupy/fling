import SwiftUI

struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case layout = "Window Layout"
        case gestures = "Gestures"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .layout: "rectangle.split.2x1"
            case .gestures: "hand.draw"
            }
        }
    }

    @State private var selection: Page? = .layout
    @State private var draft = SettingsDraft()
    @State private var message = ""
    @State private var hasError = false

    init(page: Page = .layout) {
        _selection = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationTitle("Fling")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if selection != .general {
                        SettingsPreview(draft: draft)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.bar)
                        Divider()
                    }
                    Form {
                        switch selection ?? .layout {
                        case .general: GeneralSettings()
                        case .layout: layout
                        case .gestures: gestures
                        }
                    }
                    .formStyle(.grouped)
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .onSubmit(save)
                    if selection != .general {
                        Divider()
                        footer
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .navigationTitle((selection ?? .layout).rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var layout: some View {
        Group {
            Section {
                PercentageTokenField("Edge sizes", text: $draft.edgeSizes)
                PercentageTokenField("Centre sizes", text: $draft.centerSizes)
            } header: {
                Text("Window sizes")
            } footer: {
                Text("Type a percentage and press Return to add it. Pinch or stretch to step through the sizes.")
            }

            Section("Spacing") {
                SpacingBoxModel(horizontal: $draft.horizontalPadding,
                                vertical: $draft.verticalPadding,
                                gap: $draft.windowGap)
            }
        }
    }

    private var gestures: some View {
        Group {
            Section {
                sensitivity("Fling distance", value: $draft.moveThreshold)
                sensitivity("Pinch and stretch", value: $draft.scaleThreshold)
            } header: {
                Text("Sensitivity")
            } footer: {
                Text("Lower values respond sooner. Higher values need a more deliberate gesture.")
            }
            Section("Feedback") {
                Toggle("Haptic feedback", isOn: $draft.hapticsEnabled)
                    .toggleStyle(.switch)
            }
            Section("Four-finger gestures") {
                LabeledContent("First fling", value: "Snap towards an edge at the default size")
                LabeledContent("Correction", value: "Step through positions along either axis")
                Text("Pause, reverse, or fling again to start corrections: Left ⅓ ↔ Left ½ ↔ Left ⅔ ↔ Centre ↔ Right ⅔ ↔ Right ½ ↔ Right ⅓. Further movement at either end fills the screen. Up/down uses top/bottom positions. Custom edge sizes replace these fractions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Pinch or stretch", value: "Change window size")
                LabeledContent("Quick left–right–left scrub", value: "Restore the pre-snap frame")
                LabeledContent("Pinch past smallest size", value: "Send to Stage Manager sidebar")
                Text("Lift to send the window. Stretch back before lifting to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sensitivity(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title) {
                Text(value.wrappedValue / 100, format: .percent.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
            Slider(value: value, in: 2...30) {
                Text(title)
            } minimumValueLabel: {
                Text("2%")
            } maximumValueLabel: {
                Text("30%")
            }
            .labelsHidden()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.isEmpty ? "Changes apply to your next gesture." : message)
                .font(.caption)
                .foregroundStyle(hasError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Restore Defaults") {
                    SettingsStore.shared.reset()
                    draft = SettingsDraft()
                    hasError = false
                    message = "Defaults restored."
                }
                Spacer()
                Button("Apply", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func save() {
        if let error = draft.save() {
            hasError = true
            message = error
        } else {
            draft = SettingsDraft()
            hasError = false
            message = "Settings saved."
        }
    }
}
