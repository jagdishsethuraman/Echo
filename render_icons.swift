import AppKit

func renderIcon1(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    // Background Squircle
    let rect = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let cornerRadius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    
    // Dark Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    
    // Border Highlight
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.4).cgColor)
    ctx.setLineWidth(size * 0.012)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Sonic Pulse E Wave Arcs
    ctx.saveGState()
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    
    // Gradient for strokes
    let strokeColors = [
        NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor,
        NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1.0).cgColor,
        NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0).cgColor
    ] as CFArray
    let strokeGrad = CGGradient(colorsSpace: colorSpace, colors: strokeColors, locations: [0.0, 0.5, 1.0])!
    
    ctx.setLineCap(.round)
    ctx.setLineWidth(size * 0.05)
    
    // Outer arc
    let outerArc = CGMutablePath()
    outerArc.addArc(center: CGPoint(x: size * 0.42, y: size * 0.5), radius: size * 0.24, startAngle: 1.0, endAngle: -1.0, clockwise: true)
    ctx.addPath(outerArc)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(strokeGrad, start: CGPoint(x: size * 0.2, y: size * 0.8), end: CGPoint(x: size * 0.8, y: size * 0.2), options: [])
    ctx.restoreGState()
    
    // Inner arc
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(size * 0.045)
    let innerArc = CGMutablePath()
    innerArc.addArc(center: CGPoint(x: size * 0.42, y: size * 0.5), radius: size * 0.14, startAngle: 1.0, endAngle: -1.0, clockwise: true)
    ctx.addPath(innerArc)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(strokeGrad, start: CGPoint(x: size * 0.2, y: size * 0.8), end: CGPoint(x: size * 0.8, y: size * 0.2), options: [])
    ctx.restoreGState()
    
    // Center bar
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(size * 0.045)
    let centerBar = CGMutablePath()
    centerBar.move(to: CGPoint(x: size * 0.42, y: size * 0.5))
    centerBar.addLine(to: CGPoint(x: size * 0.60, y: size * 0.5))
    ctx.addPath(centerBar)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(strokeGrad, start: CGPoint(x: size * 0.2, y: size * 0.8), end: CGPoint(x: size * 0.8, y: size * 0.2), options: [])
    ctx.restoreGState()
    
    // Pulsing core dot
    ctx.saveGState()
    ctx.setFillColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor)
    ctx.setShadow(offset: .zero, blur: size * 0.04, color: NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.9).cgColor)
    ctx.fillEllipse(in: CGRect(x: size * 0.28, y: size * 0.47, width: size * 0.06, height: size * 0.06))
    ctx.restoreGState()
    
    img.unlockFocus()
    return img
}

func renderIcon2(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    let rect = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let cornerRadius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()
    
    // Border
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 0.4).cgColor)
    ctx.setLineWidth(size * 0.012)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Left Mic wave (Cyan)
    ctx.saveGState()
    let leftCircle = CGRect(x: size * 0.24, y: size * 0.28, width: size * 0.44, height: size * 0.44)
    ctx.setStrokeColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.9).cgColor)
    ctx.setFillColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.12).cgColor)
    ctx.setLineWidth(size * 0.04)
    ctx.fillEllipse(in: leftCircle)
    ctx.strokeEllipse(in: leftCircle)
    ctx.restoreGState()
    
    // Right Meeting wave (Purple)
    ctx.saveGState()
    let rightCircle = CGRect(x: size * 0.32, y: size * 0.28, width: size * 0.44, height: size * 0.44)
    ctx.setStrokeColor(NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 0.9).cgColor)
    ctx.setFillColor(NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 0.12).cgColor)
    ctx.setLineWidth(size * 0.04)
    ctx.fillEllipse(in: rightCircle)
    ctx.strokeEllipse(in: rightCircle)
    ctx.restoreGState()
    
    // Glowing focal lens center
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setShadow(offset: .zero, blur: size * 0.06, color: NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: size * 0.46, y: size * 0.46, width: size * 0.08, height: size * 0.08))
    ctx.restoreGState()
    
    img.unlockFocus()
    return img
}

func renderIcon3(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    let rect = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let cornerRadius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).cgColor,
        NSColor(red: 0.01, green: 0.01, blue: 0.02, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()
    
    // Border
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.4).cgColor)
    ctx.setLineWidth(size * 0.012)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Möbius Sound Ribbon
    ctx.saveGState()
    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: size * 0.26, y: size * 0.58))
    ribbon.addCurve(to: CGPoint(x: size * 0.60, y: size * 0.74), control1: CGPoint(x: size * 0.26, y: size * 0.74), control2: CGPoint(x: size * 0.44, y: size * 0.74))
    ribbon.addCurve(to: CGPoint(x: size * 0.50, y: size * 0.50), control1: CGPoint(x: size * 0.76, y: size * 0.74), control2: CGPoint(x: size * 0.76, y: size * 0.50))
    ribbon.addCurve(to: CGPoint(x: size * 0.40, y: size * 0.26), control1: CGPoint(x: size * 0.24, y: size * 0.50), control2: CGPoint(x: size * 0.24, y: size * 0.26))
    ribbon.addCurve(to: CGPoint(x: size * 0.74, y: size * 0.42), control1: CGPoint(x: size * 0.56, y: size * 0.26), control2: CGPoint(x: size * 0.74, y: size * 0.26))
    
    ctx.setLineCap(.round)
    ctx.setLineWidth(size * 0.055)
    
    let brassColors = [
        NSColor(red: 0.96, green: 0.62, blue: 0.05, alpha: 1.0).cgColor,
        NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0).cgColor,
        NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1.0).cgColor
    ] as CFArray
    let brassGrad = CGGradient(colorsSpace: colorSpace, colors: brassColors, locations: [0.0, 0.5, 1.0])!
    
    ctx.addPath(ribbon)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(brassGrad, start: CGPoint(x: size * 0.2, y: size * 0.2), end: CGPoint(x: size * 0.8, y: size * 0.8), options: [])
    ctx.restoreGState()
    
    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, path: String) {
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try! png.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path) (\(png.count) bytes)")
    }
}

let artifactDir = "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3"
let devDocsDir = "/Users/ragavij/Documents/Developer/dev_docs"

let icon1 = renderIcon1(size: 512)
let icon2 = renderIcon2(size: 512)
let icon3 = renderIcon3(size: 512)

savePNG(image: icon1, path: "\(artifactDir)/echo_icon_concept1.png")
savePNG(image: icon2, path: "\(artifactDir)/echo_icon_concept2.png")
savePNG(image: icon3, path: "\(artifactDir)/echo_icon_concept3.png")

savePNG(image: icon1, path: "\(devDocsDir)/echo_icon_concept1.png")
savePNG(image: icon2, path: "\(devDocsDir)/echo_icon_concept2.png")
savePNG(image: icon3, path: "\(devDocsDir)/echo_icon_concept3.png")
