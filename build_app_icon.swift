import AppKit

// Builds the macOS app icon (squircle + shadow) from a square source artwork
// and writes both the 1024px master and the full .iconset.
//
// Usage:
//   swift build_app_icon.swift [source.png]
//
// The default source is AppIconSource.png next to this script. The artwork is
// drawn to Apple's 824pt icon grid (100pt margins) and clipped to the standard
// squircle so any background outside the artwork is removed.

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let inputURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoRoot.appendingPathComponent("AppIconSource.png")

guard let sourceImage = NSImage(contentsOf: inputURL) else {
    print("Cannot load source image at \(inputURL.path)")
    exit(1)
}

let canvasSize = 1024
let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185 // Apple's standard for an 824px icon

func makeBitmap(size: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Could not allocate \(size)px bitmap")
        exit(1)
    }
    rep.size = NSSize(width: size, height: size)
    return rep
}

// MARK: - 1024px master

let master = makeBitmap(size: canvasSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

let squirclePath = CGPath(
    roundedRect: squircleRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

// Soft dock shadow baked into the icon, matching the previous asset.
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -10),
    blur: 22,
    color: NSColor.black.withAlphaComponent(0.42).cgColor
)
ctx.setFillColor(NSColor.black.cgColor)
ctx.addPath(squirclePath)
ctx.fillPath()
ctx.restoreGState()

// Clip the artwork to the squircle. The source is authored on the same 1024
// grid, so drawing it full-canvas aligns the artwork's edges with the mask.
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()
sourceImage.draw(
    in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
    from: .zero,
    operation: .copy,
    fraction: 1.0
)
ctx.restoreGState()

// Hairline inner rim keeps the icon separated from dark wallpapers.
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.07).cgColor)
ctx.setLineWidth(1.0)
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let masterPNG = master.representation(using: .png, properties: [:]) else {
    print("Failed to encode master PNG")
    exit(1)
}
try! masterPNG.write(to: repoRoot.appendingPathComponent("AppIcon-1024.png"))
print("Wrote AppIcon-1024.png")

// MARK: - .iconset

let iconsetURL = repoRoot.appendingPathComponent("Echo.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let rep = makeBitmap(size: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let iconContext = NSGraphicsContext.current!.cgContext
    iconContext.interpolationQuality = .high
    iconContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    master.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to encode \(name)")
        exit(1)
    }
    try! png.write(to: iconsetURL.appendingPathComponent(name))
    print("Wrote \(name) (\(size)x\(size))")
}

print("Generated iconset at \(iconsetURL.path)")
print("Next: python3 make_icns.py")
