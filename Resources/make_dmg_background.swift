import AppKit

// Background for the DMG window. Icon slots must match the Finder layout in build.sh:
// window 660×400, app icon centered at (170, 200), Applications at (490, 200) — top-left origin.
let width: CGFloat = 660
let height: CGFloat = 400
let iconY: CGFloat = height - 200
let outDir = CommandLine.arguments[1]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)

    // Light base so Finder's dark icon labels stay readable
    NSGradient(colors: [color(247, 250, 255), color(230, 237, 250)])!.draw(in: bounds, angle: -90)

    // Soft glows in the icon palette
    for (center, radius, tint) in [
        (CGPoint(x: 40, y: height - 20), 320.0, color(45, 91, 208, 0.16)),
        (CGPoint(x: width - 30, y: 30), 300.0, color(143, 166, 214, 0.30)),
        (CGPoint(x: width / 2, y: iconY), 220.0, color(28, 70, 119, 0.06)),
    ] {
        NSGradient(colors: [tint, tint.withAlphaComponent(0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    // Title
    let title = NSAttributedString(string: "Shotty", attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .bold),
        .foregroundColor: color(18, 52, 92),
        .kern: -0.4,
    ])
    let subtitle = NSAttributedString(string: "Скриншоты и запись экрана", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: color(18, 52, 92, 0.6),
    ])
    title.draw(at: CGPoint(x: (width - title.size().width) / 2, y: height - 66))
    subtitle.draw(at: CGPoint(x: (width - subtitle.size().width) / 2, y: height - 88))

    // Pale slots behind the two icons
    for x in [170.0, 490.0] {
        let slot = NSBezierPath(roundedRect: CGRect(x: x - 82, y: iconY - 106, width: 164, height: 188), xRadius: 36, yRadius: 36)
        color(255, 255, 255, 0.55).setFill()
        slot.fill()
        slot.lineWidth = 1
        color(28, 70, 119, 0.12).setStroke()
        slot.stroke()
    }

    // Arrow: dashed shaft + solid head, navy gradient
    let startX: CGFloat = 268, endX: CGFloat = 392
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: startX, y: iconY))
    shaft.line(to: CGPoint(x: endX - 12, y: iconY))
    let dashed = shaft.cgPath.copy(dashingWithPhase: 0, lengths: [9, 7])
        .copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let head = NSBezierPath()
    head.move(to: CGPoint(x: endX - 20, y: iconY + 15))
    head.line(to: CGPoint(x: endX, y: iconY))
    head.line(to: CGPoint(x: endX - 20, y: iconY - 15))
    let headPath = head.cgPath.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 10)

    cg.saveGState()
    cg.addPath(dashed)
    cg.addPath(headPath)
    cg.clip()
    NSGradient(colors: [color(143, 166, 214, 0.7), color(28, 70, 119)])!
        .draw(in: CGRect(x: startX - 5, y: iconY - 20, width: endX - startX + 10, height: 40), angle: 0)
    cg.restoreGState()

    // Hint
    let hint = NSAttributedString(string: "Перетащите Shotty в папку «Программы»", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: color(18, 52, 92, 0.6),
    ])
    hint.draw(at: CGPoint(x: (width - hint.size().width) / 2, y: 34))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try render(scale: 1).write(to: URL(fileURLWithPath: outDir).appendingPathComponent("background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: outDir).appendingPathComponent("background@2x.png"))
