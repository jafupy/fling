import SwiftUI

struct SpacingBoxModel: View {
    @Binding var horizontal: String
    @Binding var vertical: String
    @Binding var gap: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case horizontal, vertical, gap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Screen padding")
                    HStack(spacing: 16) {
                        value("Horizontal", text: $horizontal, field: .horizontal)
                        value("Vertical", text: $vertical, field: .vertical)
                    }
                }
                Spacer(minLength: 0)
                diagram(showGap: false)
            }

            Divider()

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Window gap")
                    number($gap, field: .gap, label: "Window gap in pixels")
                }
                Spacer(minLength: 0)
                diagram(showGap: true)
            }

            Text("Padding leaves space around the screen. Gap separates neighbouring windows.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func value(_ title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            number(text, field: field, label: "\(title) screen padding in pixels")
        }
    }

    private func number(_ text: Binding<String>, field: Field, label: String) -> some View {
        HStack(spacing: 5) {
            TextField("", text: text, prompt: Text("0"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .focused($focusedField, equals: field)
                .accessibilityLabel(label)
            Text("px")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func diagram(showGap: Bool) -> some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let content = bounds.insetBy(dx: 15, dy: 13)
            let windowWidth = (content.width - 10) / 2
            let emphasized = showGap ? focusedField == .gap : focusedField == .horizontal || focusedField == .vertical
            let guide = emphasized ? Color.accentColor : Color.secondary

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.quaternary, lineWidth: 1)

                ForEach(0..<2) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.045))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        }
                        .frame(width: windowWidth, height: content.height)
                        .position(x: content.minX + windowWidth / 2 + CGFloat(index) * (windowWidth + 10),
                                  y: content.midY)
                }

                Path { path in
                    if showGap {
                        let left = content.minX + windowWidth
                        let right = left + 10
                        path.move(to: CGPoint(x: left, y: bounds.midY))
                        path.addLine(to: CGPoint(x: right, y: bounds.midY))
                        for x in [left, right] {
                            path.move(to: CGPoint(x: x, y: bounds.midY - 4))
                            path.addLine(to: CGPoint(x: x, y: bounds.midY + 4))
                        }
                    } else {
                        path.move(to: CGPoint(x: 3, y: bounds.midY))
                        path.addLine(to: CGPoint(x: content.minX - 3, y: bounds.midY))
                        path.move(to: CGPoint(x: bounds.midX, y: 3))
                        path.addLine(to: CGPoint(x: bounds.midX, y: content.minY - 3))
                        path.move(to: CGPoint(x: content.maxX + 3, y: bounds.midY))
                        path.addLine(to: CGPoint(x: bounds.maxX - 3, y: bounds.midY))
                        path.move(to: CGPoint(x: bounds.midX, y: content.maxY + 3))
                        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY - 3))
                    }
                }
                .stroke(guide, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: 116, height: 70)
        .accessibilityHidden(true)
    }
}
