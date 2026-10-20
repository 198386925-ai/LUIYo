import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// A straight (non-premultiplied) RGBA pixel buffer with a top-left origin,
/// mirroring the semantics of an HTML canvas and its ImageData: colour
/// operations read and write un-premultiplied channel values, and fully
/// transparent pixels keep whatever RGB they carry unless an op writes them.
final class EngineCanvas {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
    }

    /// Renders a CGImage into this buffer (source-over, no smoothing change
    /// beyond CoreGraphics' default high-quality interpolation).
    func draw(_ image: CGImage, in rect: CGRect) {
        guard let context = makeContext() else { return }
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: rect.origin.x, y: CGFloat(height) - rect.origin.y - rect.height,
                             width: rect.width, height: rect.height)
        context.draw(image, in: flipped)
        context.restoreGState()
        readBack(from: context)
    }

    /// Draws another canvas so that its pixel (sx, sy) lands at (dx, dy),
    /// scaled by `scale` — used to place a cropped region with padding.
    func draw(_ source: EngineCanvas, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        guard let image = source.cgImage() else { return }
        let rect = CGRect(x: offsetX, y: offsetY,
                          width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
        draw(image, in: rect)
    }

    private func makeContext() -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Start from the existing pixels so partial draws composite correctly.
        if pixels.contains(where: { $0 != 0 }), let existing = cgImage() {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(existing, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        return context
    }

    private func readBack(from context: CGContext) {
        guard let raw = context.data else { return }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let r = buffer[i * 4], g = buffer[i * 4 + 1], b = buffer[i * 4 + 2], a = buffer[i * 4 + 3]
            if a == 0 {
                pixels[i * 4] = 0; pixels[i * 4 + 1] = 0; pixels[i * 4 + 2] = 0; pixels[i * 4 + 3] = 0
            } else if a == 255 {
                pixels[i * 4] = r; pixels[i * 4 + 1] = g; pixels[i * 4 + 2] = b; pixels[i * 4 + 3] = a
            } else {
                let af = Int(a)
                pixels[i * 4] = UInt8(min(255, (Int(r) * 255 + af / 2) / af))
                pixels[i * 4 + 1] = UInt8(min(255, (Int(g) * 255 + af / 2) / af))
                pixels[i * 4 + 2] = UInt8(min(255, (Int(b) * 255 + af / 2) / af))
                pixels[i * 4 + 3] = a
            }
        }
    }

    func cgImage() -> CGImage? {
        var premultiplied = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let a = pixels[i * 4 + 3]
            if a == 255 {
                premultiplied[i * 4] = pixels[i * 4]
                premultiplied[i * 4 + 1] = pixels[i * 4 + 1]
                premultiplied[i * 4 + 2] = pixels[i * 4 + 2]
            } else if a > 0 {
                let af = Int(a)
                premultiplied[i * 4] = UInt8((Int(pixels[i * 4]) * af + 127) / 255)
                premultiplied[i * 4 + 1] = UInt8((Int(pixels[i * 4 + 1]) * af + 127) / 255)
                premultiplied[i * 4 + 2] = UInt8((Int(pixels[i * 4 + 2]) * af + 127) / 255)
            }
            premultiplied[i * 4 + 3] = a
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(premultiplied) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    func pngData() -> Data? {
        guard let image = cgImage() else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    // MARK: - Pixel operations (canvas parity: only pixels with alpha > 0 change)

    func recolor(hex: String) {
        let (r, g, b) = EngineImageProcessing.parseHex(hex)
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b
        }
    }

    func darken(factor: Double = 0.68) {
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            pixels[i] = UInt8((Double(pixels[i]) * factor).rounded())
            pixels[i + 1] = UInt8((Double(pixels[i + 1]) * factor).rounded())
            pixels[i + 2] = UInt8((Double(pixels[i + 2]) * factor).rounded())
        }
    }

    func invert() {
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            pixels[i] = 255 - pixels[i]
            pixels[i + 1] = 255 - pixels[i + 1]
            pixels[i + 2] = 255 - pixels[i + 2]
        }
    }
}

enum EngineImageProcessing {
    static func parseHex(_ hex: String) -> (UInt8, UInt8, UInt8) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count >= 6, let value = UInt32(text.prefix(6), radix: 16) else { return (0, 0, 0) }
        return (UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
    }

    static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    /// drawToCanvas(file) without a target size: fit the whole image into a
    /// 128×128 canvas, centred, keeping the aspect ratio.
    static func drawToCanvas(_ image: CGImage) -> EngineCanvas {
        let size = 128
        let canvas = EngineCanvas(width: size, height: size)
        let scale = min(CGFloat(size) / CGFloat(image.width), CGFloat(size) / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        canvas.draw(image, in: CGRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2, width: w, height: h))
        return canvas
    }

    /// drawToIconCanvas: cap the source at 2048px, trim transparent borders
    /// (alpha > 8), then fit the trimmed region into [width, height] with a
    /// 6% padding on every side.
    static func drawToIconCanvas(_ image: CGImage, width: Int, height: Int) -> EngineCanvas {
        let cap = min(1, 2048 / CGFloat(max(image.width, image.height)))
        let sw = max(1, Int((CGFloat(image.width) * cap).rounded()))
        let sh = max(1, Int((CGFloat(image.height) * cap).rounded()))
        let source = EngineCanvas(width: sw, height: sh)
        source.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        var left = sw, top = sh, right = -1, bottom = -1
        for y in 0..<sh {
            for x in 0..<sw where source.pixels[(y * sw + x) * 4 + 3] > 8 {
                if x < left { left = x }
                if x > right { right = x }
                if y < top { top = y }
                if y > bottom { bottom = y }
            }
        }
        if right < left { left = 0; top = 0; right = sw - 1; bottom = sh - 1 }
        let cw = right - left + 1, ch = bottom - top + 1
        let canvas = EngineCanvas(width: width, height: height)
        let padX = CGFloat(width) * 0.06, padY = CGFloat(height) * 0.06
        let scale = min((CGFloat(width) - padX * 2) / CGFloat(cw), (CGFloat(height) - padY * 2) / CGFloat(ch))
        let destW = CGFloat(cw) * scale, destH = CGFloat(ch) * scale
        let destX = (CGFloat(width) - destW) / 2, destY = (CGFloat(height) - destH) / 2
        canvas.draw(source, scale: scale, offsetX: destX - CGFloat(left) * scale, offsetY: destY - CGFloat(top) * scale)
        return canvas
    }

    static func draw(_ image: CGImage, canvasSize: (Int, Int)?) -> EngineCanvas {
        if let canvasSize { return drawToIconCanvas(image, width: canvasSize.0, height: canvasSize.1) }
        return drawToCanvas(image)
    }

    /// thumbnailFor: scale to at most 1024px, crop to the alpha bounds with a
    /// 4% margin, and return the cropped PNG.
    static func thumbnailPNG(for image: CGImage) -> Data? {
        let scale = min(1, 1024 / CGFloat(max(image.width, image.height)))
        let sw = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let sh = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let canvas = EngineCanvas(width: sw, height: sh)
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        var left = sw, top = sh, right = -1, bottom = -1
        for y in 0..<sh {
            for x in 0..<sw where canvas.pixels[(y * sw + x) * 4 + 3] > 0 {
                if x < left { left = x }
                if x > right { right = x }
                if y < top { top = y }
                if y > bottom { bottom = y }
            }
        }
        if right < left { return canvas.pngData() }
        let boundsW = right - left + 1, boundsH = bottom - top + 1
        let inset = max(1, Int(ceil(Double(max(boundsW, boundsH)) * 0.04)))
        let crop = EngineCanvas(width: boundsW + inset * 2, height: boundsH + inset * 2)
        crop.draw(canvas, scale: 1, offsetX: CGFloat(inset - left), offsetY: CGFloat(inset - top))
        return crop.pngData()
    }
}
