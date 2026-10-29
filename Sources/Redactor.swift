import AppKit
import CoreImage

/// Renders blur and pixelate regions from the original screenshot pixels.
/// Results are cached per region and strength, since the canvas redraws on every mouse move.
final class Redactor {
    private let source: CGImage?
    private let scale: CGFloat
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let cache = NSCache<NSString, NSImage>()

    init(image: NSImage) {
        source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        scale = source.map { CGFloat($0.width) / max(image.size.width, 1) } ?? 1
    }

    /// Expects the canvas's flipped context; `rect` is in image points.
    func draw(_ annotation: Annotation) {
        let rect = annotation.rect.integral
        guard rect.width >= 1, rect.height >= 1, let image = redacted(annotation.kind, rect: rect, strength: annotation.lineWidth) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.none])
    }

    private func redacted(_ kind: Annotation.Kind, rect: CGRect, strength: CGFloat) -> NSImage? {
        let key = "\(kind)|\(rect.debugDescription)|\(strength)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        // CGImage cropping uses a top-left origin, same as the flipped canvas.
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                               width: rect.width * scale, height: rect.height * scale).integral
        guard let source, let crop = source.cropping(to: pixelRect) else { return nil }
        let input = CIImage(cgImage: crop)
        let extent = input.extent

        // Both effects stay strong even at the thinnest setting: weak blur or small blocks can be reversed.
        let output: CIImage?
        switch kind {
        case .pixelate:
            let block = (8 + strength * 1.5) * scale
            let filter = CIFilter(name: "CIPixellate")
            // CIPixellate samples one pixel per block; blurring first makes each block the area's average.
            filter?.setValue(input.clampedToExtent().applyingGaussianBlur(sigma: block / 2), forKey: kCIInputImageKey)
            filter?.setValue(block, forKey: kCIInputScaleKey)
            filter?.setValue(CIVector(x: extent.minX, y: extent.minY), forKey: kCIInputCenterKey)
            output = filter?.outputImage?.cropped(to: extent)
        default:
            let radius = (6 + strength * 1.5) * scale
            // A second pass smooths out the faint letter shapes that survive a single blur.
            output = input.clampedToExtent()
                .applyingGaussianBlur(sigma: radius)
                .applyingGaussianBlur(sigma: radius / 2)
                .cropped(to: extent)
        }
        guard let output, let cg = context.createCGImage(output, from: extent) else { return nil }
        let image = NSImage(cgImage: cg, size: rect.size)
        cache.setObject(image, forKey: key)
        return image
    }
}
