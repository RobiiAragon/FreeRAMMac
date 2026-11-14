import AppKit

// Reproducible, code-drawn application icon. No downloaded assets.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let sizes = [16, 32, 128, 256, 512]
var images: [[String: String]] = []
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        let factor = CGFloat(pixels) / 1024
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: factor, y: factor)
        let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 194, yRadius: 194)
        NSGradient(starting: NSColor(red: 0.12, green: 0.25, blue: 0.28, alpha: 1), ending: NSColor(red: 0.04, green: 0.11, blue: 0.16, alpha: 1))!
            .draw(in: background, angle: -75)
        NSColor(red: 0.42, green: 0.91, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 238, y: 298, width: 548, height: 428), xRadius: 50, yRadius: 50).fill()
        for x in stride(from: 292, through: 732, by: 88) {
            NSBezierPath(roundedRect: NSRect(x: x, y: 246, width: 34, height: 62), xRadius: 10, yRadius: 10).fill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 716, width: 34, height: 62), xRadius: 10, yRadius: 10).fill()
        }
        NSColor(red: 0.05, green: 0.23, blue: 0.23, alpha: 1).setFill()
        for x in [326, 466, 606] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 418, width: 92, height: 190), xRadius: 14, yRadius: 14).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)@\(scale)x.png"
        try representation.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let metadata: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Contents.json"))
