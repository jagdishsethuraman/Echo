import AppKit

func renderApprovedHybrid(width: CGFloat = 1000, height: CGFloat = 620) -> NSImage {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    // Window canvas
    let windowRect = CGRect(x: 20, y: 20, width: width - 40, height: height - 40)
    let clipPath = CGPath(roundedRect: windowRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(clipPath)
    ctx.clip()
    
    // Deep Swiss Obsidian Background
    ctx.setFillColor(NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0).cgColor)
    ctx.fill(windowRect)
    
    // Titlebar
    let titlebarRect = CGRect(x: windowRect.minX, y: windowRect.maxY - 40, width: windowRect.width, height: 40)
    ctx.setFillColor(NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0).cgColor)
    ctx.fill(titlebarRect)
    
    // Titlebar border
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.25).cgColor)
    ctx.setLineWidth(1)
    ctx.strokeLineSegments(between: [
        CGPoint(x: titlebarRect.minX, y: titlebarRect.minY),
        CGPoint(x: titlebarRect.maxX, y: titlebarRect.minY)
    ])
    
    // Window Dots
    let dotY = titlebarRect.midY - 6
    let dots: [(CGFloat, NSColor)] = [
        (windowRect.minX + 16, NSColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1.0)),
        (windowRect.minX + 34, NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0)),
        (windowRect.minX + 52, NSColor(red: 0.15, green: 0.79, blue: 0.25, alpha: 1.0))
    ]
    for (dotX, dotColor) in dots {
        ctx.setFillColor(dotColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: dotX, y: dotY, width: 12, height: 12))
    }
    
    // Title & Atelier Badge
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0)
    ]
    NSAttributedString(string: "ECHO // ACOUSTIC STUDIO", attributes: titleAttrs)
        .draw(at: CGPoint(x: windowRect.minX + 80, y: titlebarRect.midY - 7))
    
    let subTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(white: 0.6, alpha: 1.0)
    ]
    NSAttributedString(string: "·  Executive Architecture Review", attributes: subTitleAttrs)
        .draw(at: CGPoint(x: windowRect.minX + 245, y: titlebarRect.midY - 7))
    
    // Right Hardware Indicators in Titlebar
    let hudAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
        .foregroundColor: NSColor(white: 0.7, alpha: 1.0)
    ]
    NSAttributedString(string: "MIC [16kHz]   |   LOOPBACK [SCK]   |", attributes: hudAttrs)
        .draw(at: CGPoint(x: windowRect.maxX - 310, y: titlebarRect.midY - 6))
    
    let recAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
    ]
    NSAttributedString(string: "● REC 14:02", attributes: recAttrs)
        .draw(at: CGPoint(x: windowRect.maxX - 96, y: titlebarRect.midY - 6))
    
    // Content Layout: Bento Grid Split-Pane
    let contentRect = CGRect(x: windowRect.minX, y: windowRect.minY, width: windowRect.width, height: windowRect.height - 40)
    let splitX = contentRect.minX + contentRect.width * 0.63
    let leftRect = CGRect(x: contentRect.minX, y: contentRect.minY, width: splitX - contentRect.minX, height: contentRect.height)
    let rightRect = CGRect(x: splitX, y: contentRect.minY, width: contentRect.maxX - splitX, height: contentRect.height)
    
    // Vertical Brass Divider
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.22).cgColor)
    ctx.setLineWidth(1)
    ctx.strokeLineSegments(between: [
        CGPoint(x: splitX, y: contentRect.minY),
        CGPoint(x: splitX, y: contentRect.maxY)
    ])
    
    // Left Pane: Subheader
    let sectionHeaderAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
        .foregroundColor: NSColor(white: 0.45, alpha: 1.0)
    ]
    NSAttributedString(string: "CONVERSATION STREAM", attributes: sectionHeaderAttrs)
        .draw(at: CGPoint(x: leftRect.minX + 24, y: leftRect.maxY - 28))
    
    let rtfAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.85)
    ]
    NSAttributedString(string: "PHONON-2 · 37.7X RTF", attributes: rtfAttrs)
        .draw(at: CGPoint(x: leftRect.maxX - 160, y: leftRect.maxY - 28))
    
    // Utterance 1 (You) - Swiss Quote with Warm Brass Accent Rail
    let u1Y = leftRect.maxY - 146
    let u1Rect = CGRect(x: leftRect.minX + 20, y: u1Y, width: leftRect.width - 40, height: 102)
    let u1Path = CGPath(roundedRect: u1Rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(u1Path)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 0.9).cgColor)
    ctx.fillPath()
    ctx.addPath(u1Path)
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.35).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    
    // Left vertical brass bar
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0).cgColor)
    ctx.setLineWidth(3)
    ctx.strokeLineSegments(between: [
        CGPoint(x: u1Rect.minX + 12, y: u1Rect.maxY - 12),
        CGPoint(x: u1Rect.minX + 12, y: u1Rect.minY + 12)
    ])
    ctx.restoreGState()
    
    let youTagAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
        .foregroundColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0)
    ]
    NSAttributedString(string: "YOU · 14:02:15 · MIC TAP 16kHz", attributes: youTagAttrs)
        .draw(at: CGPoint(x: u1Rect.minX + 24, y: u1Rect.maxY - 24))
    
    let quoteAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .light),
        .foregroundColor: NSColor(white: 0.96, alpha: 1.0)
    ]
    let para = NSMutableParagraphStyle()
    para.lineSpacing = 4
    var qAttrs = quoteAttrs
    qAttrs[.paragraphStyle] = para
    let q1 = "\"We have benchmarked the Phonon-2 engine on Apple Silicon. The INT6 quantization runs under 600MB RAM with zero silence hallucinations.\""
    NSAttributedString(string: q1, attributes: qAttrs)
        .draw(in: CGRect(x: u1Rect.minX + 24, y: u1Rect.minY + 10, width: u1Rect.width - 36, height: 56))
    
    // Utterance 2 (Attendee) - Swiss Quote with Lavender Accent Rail
    let u2Y = u1Y - 122
    let u2Rect = CGRect(x: leftRect.minX + 20, y: u2Y, width: leftRect.width - 40, height: 102)
    let u2Path = CGPath(roundedRect: u2Rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(u2Path)
    ctx.setFillColor(NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 0.8).cgColor)
    ctx.fillPath()
    ctx.addPath(u2Path)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    
    ctx.setStrokeColor(NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0).cgColor)
    ctx.setLineWidth(3)
    ctx.strokeLineSegments(between: [
        CGPoint(x: u2Rect.minX + 12, y: u2Rect.maxY - 12),
        CGPoint(x: u2Rect.minX + 12, y: u2Rect.minY + 12)
    ])
    ctx.restoreGState()
    
    let attendeeTagAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
        .foregroundColor: NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0)
    ]
    NSAttributedString(string: "SARAH [PRODUCT LEAD] · 14:02:22 · SCREENCAPTUREKIT", attributes: attendeeTagAttrs)
        .draw(at: CGPoint(x: u2Rect.minX + 24, y: u2Rect.maxY - 24))
    
    let q2 = "\"That is an enormous speedup over Whisper small. Can we support both push-to-talk cursor dictation and meeting recording in one app?\""
    NSAttributedString(string: q2, attributes: qAttrs)
        .draw(in: CGRect(x: u2Rect.minX + 24, y: u2Rect.minY + 10, width: u2Rect.width - 36, height: 56))
    
    // Utterance 3 (You)
    let u3Y = u2Y - 122
    let u3Rect = CGRect(x: leftRect.minX + 20, y: u3Y, width: leftRect.width - 40, height: 102)
    let u3Path = CGPath(roundedRect: u3Rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(u3Path)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 0.9).cgColor)
    ctx.fillPath()
    ctx.addPath(u3Path)
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.35).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0).cgColor)
    ctx.setLineWidth(3)
    ctx.strokeLineSegments(between: [
        CGPoint(x: u3Rect.minX + 12, y: u3Rect.maxY - 12),
        CGPoint(x: u3Rect.minX + 12, y: u3Rect.minY + 12)
    ])
    ctx.restoreGState()
    
    NSAttributedString(string: "YOU · 14:02:30 · MIC TAP 16kHz", attributes: youTagAttrs)
        .draw(at: CGPoint(x: u3Rect.minX + 24, y: u3Rect.maxY - 24))
    
    let q3 = "\"Yes, Echo unifies both modes under one status-bar binary. Quick dictation pastes at cursor; meeting mode saves structured notes here.\""
    NSAttributedString(string: q3, attributes: qAttrs)
        .draw(in: CGRect(x: u3Rect.minX + 24, y: u3Rect.minY + 10, width: u3Rect.width - 36, height: 56))
    
    // Right Pane: Live AI Notes (Swiss Bento)
    NSAttributedString(string: "LIVE AI EXECUTIVE NOTES", attributes: sectionHeaderAttrs)
        .draw(at: CGPoint(x: rightRect.minX + 20, y: rightRect.maxY - 28))
    
    // Decisions Box
    let decRect = CGRect(x: rightRect.minX + 20, y: rightRect.maxY - 190, width: rightRect.width - 40, height: 148)
    let decPath = CGPath(roundedRect: decRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(decPath)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.addPath(decPath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let brassHeadAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0)
    ]
    NSAttributedString(string: "Key Decisions", attributes: brassHeadAttrs)
        .draw(at: CGPoint(x: decRect.minX + 14, y: decRect.maxY - 24))
    
    let bulletAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(white: 0.8, alpha: 1.0)
    ]
    let decText = """
    • Single unified binary selected over 2 separate apps.
    • Phonon-2 INT6 locked as primary speech engine.
    • Swiss Atelier theme with Bento split-pane layout.
    • Stag bugle icon approved as brand visual identity.
    """
    NSAttributedString(string: decText, attributes: bulletAttrs)
        .draw(in: CGRect(x: decRect.minX + 14, y: decRect.minY + 8, width: decRect.width - 28, height: 104))
    
    // Action Items Box
    let actRect = CGRect(x: rightRect.minX + 20, y: decRect.minY - 170, width: rightRect.width - 40, height: 154)
    let actPath = CGPath(roundedRect: actRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(actPath)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.addPath(actPath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let whiteHeadAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    NSAttributedString(string: "Action Items", attributes: whiteHeadAttrs)
        .draw(at: CGPoint(x: actRect.minX + 14, y: actRect.maxY - 24))
    
    let actText = """
    [✓] Benchmark Swift loopback engine (0.53s)
    [✓] Build floating HUD & push-to-talk hotkey
    [✓] Deploy dual-channel CoreAudio loopback
    [✓] Package production AppIcon.icns & Echo.app
    [✓] Wire Adaptive Pill timer into MenuBar
    """
    NSAttributedString(string: actText, attributes: bulletAttrs)
        .draw(in: CGRect(x: actRect.minX + 14, y: actRect.minY + 8, width: actRect.width - 28, height: 110))
    
    // Export Button
    let btnRect = CGRect(x: rightRect.minX + 20, y: actRect.minY - 56, width: rightRect.width - 40, height: 42)
    let btnPath = CGPath(roundedRect: btnRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(btnPath)
    ctx.setFillColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    let btnTextAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    let btnStr = NSAttributedString(string: "Export Notes to Obsidian (.md)", attributes: btnTextAttrs)
    let bSize = btnStr.size()
    btnStr.draw(at: CGPoint(x: btnRect.midX - bSize.width / 2, y: btnRect.midY - bSize.height / 2))
    
    img.unlockFocus()
    return img
}

let artifactDir = "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3"
let devDocsDir = "/Users/ragavij/Documents/Developer/dev_docs"

let approvedUI = renderApprovedHybrid()

if let tiff = approvedUI.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "\(artifactDir)/echo_approved_swiss_bento_ui.png"))
    try! png.write(to: URL(fileURLWithPath: "\(devDocsDir)/echo_approved_swiss_bento_ui.png"))
    print("Rendered approved Swiss Bento UI mockup (\(png.count) bytes)")
}
