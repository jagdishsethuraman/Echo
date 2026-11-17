import AppKit

let inputPath = "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3/.user_uploaded/media_1794852255988_55a2e428.jpg"
guard let srcImage = NSImage(contentsOfFile: inputPath) else {
    print("Cannot load source image")
    exit(1)
}

let canvasSize: CGFloat = 1024
let squircleRect = CGRect(x: 100, y: 101, width: 824, height: 824)
let cornerRadius: CGFloat = 185.0 // Apple standard for 824px squircle

let outputImage = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
outputImage.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Drop shadow for macOS Dock
ctx.saveGState()
let shadowPath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor(white: 0, alpha: 0.45).cgColor)
ctx.setFillColor(NSColor.black.cgColor)
ctx.addPath(shadowPath)
ctx.fillPath()
ctx.restoreGState()

// Clip to squircle
ctx.saveGState()
let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(squirclePath)
ctx.clip()

// Draw source image exactly
srcImage.draw(in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

// Add crisp subtle inner border
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
ctx.setLineWidth(1.5)
ctx.strokePath()
ctx.restoreGState()

outputImage.unlockFocus()

// Save 1024x1024 PNG
let artifactDir = "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3"
let devDocsDir = "/Users/ragavij/Documents/Developer/dev_docs"
let echoAppDir = "/Users/ragavij/Documents/Developer/Echo"

guard let tiff = outputImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    print("Failed to encode PNG")
    exit(1)
}

try! pngData.write(to: URL(fileURLWithPath: "\(artifactDir)/echo_app_icon_1024.png"))
try! pngData.write(to: URL(fileURLWithPath: "\(devDocsDir)/echo_app_icon_1024.png"))
print("Saved 1024x1024 icon PNG")

// Now generate iconset
let iconsetPath = "\(echoAppDir)/Echo.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
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

for (name, s) in sizes {
    let resized = NSImage(size: NSSize(width: s, height: s))
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    outputImage.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .copy, fraction: 1.0)
    resized.unlockFocus()
    
    if let rTiff = resized.tiffRepresentation,
       let rRep = NSBitmapImageRep(data: rTiff),
       let rPng = rRep.representation(using: .png, properties: [:]) {
        let filePath = "\(iconsetPath)/\(name)"
        try! rPng.write(to: URL(fileURLWithPath: filePath))
    }
}

print("Generated full iconset at \(iconsetPath)")
