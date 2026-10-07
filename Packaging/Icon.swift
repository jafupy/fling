import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

        let background = NSBezierPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928),
                                      xRadius: 208, yRadius: 208)
        NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.30, blue: 0.95, alpha: 1),
                   ending: NSColor(srgbRed: 0.12, green: 0.70, blue: 1, alpha: 1))!
            .draw(in: background, angle: 90)
        let echo = NSBezierPath(roundedRect: CGRect(x: 192, y: 260, width: 568, height: 454),
                                xRadius: 44, yRadius: 44)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        echo.lineWidth = 22
        echo.stroke()
        let window = NSBezierPath(roundedRect: CGRect(x: 264, y: 330, width: 568, height: 454),
                                  xRadius: 44, yRadius: 44)
        NSColor.white.withAlphaComponent(0.14).setFill()
        window.fill()
        NSColor.white.setStroke()
        window.lineWidth = 22
        window.stroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: 276, y: 684))
        divider.line(to: CGPoint(x: 820, y: 684))
        divider.lineWidth = 16
        divider.stroke()
        NSColor.white.setFill()
        for x in [314, 362, 410, 458] {
            NSBezierPath(ovalIn: CGRect(x: x, y: 716, width: 20, height: 20)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
