import SwiftUI

struct PercentageTokenField: View {
    private let title: String
    @Binding private var text: String
    @State private var values: [Double]
    @State private var pending: String
    @State private var published: String
    @State private var error: String?

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
        let parsed = Self.parse(text.wrappedValue)
        _values = State(initialValue: parsed ?? [])
        _pending = State(initialValue: parsed == nil ? text.wrappedValue : "")
        _published = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 4) {
                TokenFlow {
                    ForEach(values, id: \.self) { value in
                        HStack(spacing: 3) {
                            Text(Self.format(value) + "%")
                                .monospacedDigit()
                            Button {
                                values.removeAll { $0 == value }
                                error = nil
                                publish()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 18, height: 20)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(Self.format(value)) percent from \(title)")
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 3)
                        .background(.quaternary, in: Capsule())
                    }
                    TextField("", text: Binding(
                        get: { pending },
                        set: { input in
                            pending = input
                            error = nil
                            if input.contains(",") { commit() }
                            else { publish() }
                        }
                    ), prompt: Text("Add %"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .frame(width: 64, height: 24)
                    .accessibilityLabel("Add percentage to \(title)")
                    .onSubmit { commit() }
                    .submitScope()
                }
                .padding(5)
                .background(.background, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator, lineWidth: 0.5))
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 340, alignment: .leading)
        }
        .onChange(of: text) { _, newValue in
            guard newValue != published else { return }
            synchronize(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsStore.changedNotification)) { _ in
            // Apply can keep the same serialized text while committing the pending entry.
            synchronize(text)
        }
    }

    private func synchronize(_ raw: String) {
        let parsed = Self.parse(raw)
        values = parsed ?? []
        pending = parsed == nil ? raw : ""
        published = raw
        error = nil
    }

    private func commit() {
        let input = Self.clean(pending).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        // A final comma submits the current value; interior empty values stay invalid.
        let list = input.hasSuffix(",") ? String(input.dropLast()) : input
        let combined = (values.map(Self.format) + [list]).joined(separator: ", ")
        guard let parsed = Self.parse(combined) else {
            error = "Use up to 12 sizes, from 10% to 100%."
            publish()
            return
        }
        values = parsed
        pending = ""
        error = nil
        publish()
    }

    private func publish() {
        let input = Self.clean(pending).trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = values.map(Self.format)
        if !input.isEmpty { parts.append(input) }
        let raw = parts.joined(separator: ", ")
        published = raw
        text = raw
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "%", with: "")
    }

    private static func parse(_ value: String) -> [Double]? {
        SettingsStore.parsePercentList(value)?.map { Double($0) * 100 }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

private struct TokenFlow: Layout {
    private let spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 340, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: .unspecified)
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
