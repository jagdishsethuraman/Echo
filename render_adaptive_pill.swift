import AppKit

func renderAdaptivePillStates(width: CGFloat = 960, height: CGFloat = 280) -> NSImage {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    // Background canvas
    ctx.setFillColor(NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    let states: [(String, String, NSColor, NSColor, CGFloat, String)] = [
        ("STATE 1: IDLE (MINIMAL GLYPH - COMPACT & UNCLUTTERED)", "◉", NSColor.white, NSColor(white: 1.0, alpha: 0.08), 28, "Returns to minimal glyph when inactive"),
        ("STATE 2: QUICK DICTATION (PUSH-TO-TALK ACTIVE)", "◉ Dictating...", NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0), NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.18), 108, "Pulsing brass indicator while holding hotkey"),
        ("STATE 3: MEETING RECORDING (ADAPTIVE DURATION TIMER)", "● 14:02", NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0), NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.18), 84, "Live second-by-second MM:SS duration counter")
    ]
    
    let font = NSFont.systemFont(ofSize: 12, weight: .regular)
    let boldFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
    let wAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    
    for (i, (header, pillText, textColor, bgColor, pillW, desc)) in states.enumerated() {
        let barY = height - 80.0 - CGFloat(i) * 85.0
        let barRect = CGRect(x: 30, y: barY, width: width - 60, height: 38)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        
        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.setFillColor(NSColor(white: 0.10, alpha: 1.0).cgColor)
        ctx.fillPath()
        ctx.addPath(barPath)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
        
        // Header
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: textColor
        ]
        NSAttributedString(string: header, attributes: headAttrs)
            .draw(at: CGPoint(x: 32, y: barY + 44))
        
        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(white: 0.5, alpha: 1.0)
        ]
        NSAttributedString(string: "— \(desc)", attributes: descAttrs)
            .draw(at: CGPoint(x: 420, y: barY + 44))
        
        // Left OS items
        NSAttributedString(string: "   File   Edit   View   Window   Help", attributes: wAttrs)
            .draw(at: CGPoint(x: barRect.minX + 16, y: barRect.midY - 8))
        
        // Adaptive Pill
        let pillX = barRect.maxX - 160 - pillW
        let pillRect = CGRect(x: pillX, y: barRect.midY - 12, width: pillW, height: 24)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.saveGState()
        ctx.addPath(pillPath)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()
        ctx.addPath(pillPath)
        ctx.setStrokeColor(textColor.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
        
        let pillAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .foregroundColor: textColor
        ]
        let pStr = NSAttributedString(string: pillText, attributes: pillAttrs)
        let pSize = pStr.size()
        pStr.draw(at: CGPoint(x: pillRect.midX - pSize.width / 2, y: pillRect.midY - pSize.height / 2))
        
        // System items
        let sysAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.7, alpha: 1.0)]
        NSAttributedString(string: "Wi-Fi   100%   Mon 14:02", attributes: sysAttrs)
            .draw(at: CGPoint(x: barRect.maxX - 145, y: barRect.midY - 8))
    }
    
    img.unlockFocus()
    return img
}

let artifactDir = "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3"
let devDocsDir = "/Users/ragavij/Documents/Developer/dev_docs"

let pillImg = renderAdaptivePillStates()

if let tiff = pillImg.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "\(artifactDir)/echo_approved_adaptive_pill.png"))
    try! png.write(to: URL(fileURLWithPath: "\(devDocsDir)/echo_approved_adaptive_pill.png"))
    print("Rendered adaptive pill states mockup (\(png.count) bytes)")
}
