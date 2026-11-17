import AppKit

let url = URL(fileURLWithPath: "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3/.user_uploaded/media_1794852255988_55a2e428.jpg")
guard let image = NSImage(contentsOf: url),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("Failed to load image")
    exit(1)
}

print("Width: \(rep.pixelsWide), Height: \(rep.pixelsHigh)")
if let c = rep.colorAt(x: 10, y: 10) {
    print("Corner (10, 10): r=\(c.redComponent), g=\(c.greenComponent), b=\(c.blueComponent)")
}
if let c = rep.colorAt(x: 512, y: 120) {
    print("Squircle top (512, 120): r=\(c.redComponent), g=\(c.greenComponent), b=\(c.blueComponent)")
}
if let c = rep.colorAt(x: 512, y: 512) {
    print("Center (512, 512): r=\(c.redComponent), g=\(c.greenComponent), b=\(c.blueComponent)")
}
