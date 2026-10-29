import AppKit

// Rasterizes the vector icon (Resources/AppIcon.svg, 1024×1024 macOS icon grid) into an .iconset
let svgPath = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]

guard let icon = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
    fatalError("Не удалось прочитать \(svgPath)")
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in specs {
    try render(px).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png"))
}
