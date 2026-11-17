import AppKit

func createBaseWindow(width: CGFloat, height: CGFloat, title: String, statusRight: String = "", statusColor: NSColor = .systemRed) -> (NSImage, CGContext, CGRect) {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    // Outer rounded shadow window
    let windowRect = CGRect(x: 20, y: 20, width: width - 40, height: height - 40)
    let clipPath = CGPath(roundedRect: windowRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(clipPath)
    ctx.clip()
    
    // Background fill
    ctx.setFillColor(NSColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0).cgColor)
    ctx.fill(windowRect)
    
    // Titlebar
    let titlebarRect = CGRect(x: windowRect.minX, y: windowRect.maxY - 38, width: windowRect.width, height: 38)
    ctx.setFillColor(NSColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1.0).cgColor)
    ctx.fill(titlebarRect)
    
    // Titlebar bottom border
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.1).cgColor)
    ctx.setLineWidth(1)
    ctx.strokeLineSegments(between: [
        CGPoint(x: titlebarRect.minX, y: titlebarRect.minY),
        CGPoint(x: titlebarRect.maxX, y: titlebarRect.minY)
    ])
    
    // Window dots
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
    
    // Title text
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(white: 0.75, alpha: 1.0)
    ]
    let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
    let titleSize = titleStr.size()
    titleStr.draw(at: CGPoint(x: windowRect.midX - titleSize.width / 2, y: titlebarRect.midY - titleSize.height / 2))
    
    // Status Right
    if !statusRight.isEmpty {
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: statusColor
        ]
        let statusStr = NSAttributedString(string: statusRight, attributes: statusAttrs)
        let sSize = statusStr.size()
        statusStr.draw(at: CGPoint(x: windowRect.maxX - sSize.width - 16, y: titlebarRect.midY - sSize.height / 2))
    }
    
    let contentRect = CGRect(x: windowRect.minX, y: windowRect.minY, width: windowRect.width, height: windowRect.height - 38)
    return (img, ctx, contentRect)
}

func renderUIOptionA(width: CGFloat = 960, height: CGFloat = 580) -> NSImage {
    let (img, ctx, contentRect) = createBaseWindow(width: width, height: height, title: "Echo Meeting Studio — Q4 Product Architecture Sync", statusRight: "● REC 14:02", statusColor: .systemRed)
    
    let splitX = contentRect.minX + contentRect.width * 0.62
    let leftRect = CGRect(x: contentRect.minX, y: contentRect.minY, width: splitX - contentRect.minX, height: contentRect.height)
    let rightRect = CGRect(x: splitX, y: contentRect.minY, width: contentRect.maxX - splitX, height: contentRect.height)
    
    // Split border
    ctx.setStrokeColor(NSColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 0.6).cgColor)
    ctx.setLineWidth(1)
    ctx.strokeLineSegments(between: [
        CGPoint(x: splitX, y: contentRect.minY),
        CGPoint(x: splitX, y: contentRect.maxY)
    ])
    
    // Right panel darker background
    ctx.setFillColor(NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0).cgColor)
    ctx.fill(rightRect)
    
    // Left pane header
    let leftHeaderAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
    ]
    NSAttributedString(string: "DUAL-CHANNEL TRANSCRIPT · PHONON-2 (0.53s / 37.7x RTF)", attributes: leftHeaderAttrs)
        .draw(at: CGPoint(x: leftRect.minX + 24, y: leftRect.maxY - 32))
    
    // Bubble 1: You
    let bubble1Rect = CGRect(x: leftRect.minX + 24, y: leftRect.maxY - 140, width: leftRect.width - 48, height: 96)
    let b1Path = CGPath(roundedRect: bubble1Rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.saveGState()
    ctx.addPath(b1Path)
    ctx.setFillColor(NSColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.9).cgColor)
    ctx.fillPath()
    ctx.addPath(b1Path)
    ctx.setStrokeColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.45).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let youMetaAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
    ]
    NSAttributedString(string: "◉ [You] · 14:02:15 · Mic Tap 16kHz", attributes: youMetaAttrs)
        .draw(at: CGPoint(x: bubble1Rect.minX + 16, y: bubble1Rect.maxY - 26))
    
    let bubbleTextAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(white: 0.95, alpha: 1.0)
    ]
    let text1 = "We have benchmarked the Phonon-2 engine locally on Apple Silicon. The INT6 quantization runs under 600MB RAM with zero silence hallucinations."
    let para1 = NSMutableParagraphStyle()
    para1.lineSpacing = 4
    var bAttrs1 = bubbleTextAttrs
    bAttrs1[.paragraphStyle] = para1
    NSAttributedString(string: text1, attributes: bAttrs1)
        .draw(in: CGRect(x: bubble1Rect.minX + 16, y: bubble1Rect.minY + 12, width: bubble1Rect.width - 32, height: 54))
    
    // Bubble 2: Sarah (Meeting attendee)
    let bubble2Rect = CGRect(x: leftRect.minX + 24, y: bubble1Rect.minY - 116, width: leftRect.width - 48, height: 96)
    let b2Path = CGPath(roundedRect: bubble2Rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.saveGState()
    ctx.addPath(b2Path)
    ctx.setFillColor(NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 0.9).cgColor)
    ctx.fillPath()
    ctx.addPath(b2Path)
    ctx.setStrokeColor(NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 0.35).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let sarahMetaAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0)
    ]
    NSAttributedString(string: "◎ [Sarah — Product Lead] · 14:02:22 · Loopback Audio", attributes: sarahMetaAttrs)
        .draw(at: CGPoint(x: bubble2Rect.minX + 16, y: bubble2Rect.maxY - 26))
    
    let text2 = "That is an enormous speedup over Whisper small. Can we support both push-to-talk cursor dictation and meeting recording in one unified app?"
    NSAttributedString(string: text2, attributes: bAttrs1)
        .draw(in: CGRect(x: bubble2Rect.minX + 16, y: bubble2Rect.minY + 12, width: bubble2Rect.width - 32, height: 54))
    
    // Bubble 3: You response
    let bubble3Rect = CGRect(x: leftRect.minX + 24, y: bubble2Rect.minY - 116, width: leftRect.width - 48, height: 96)
    let b3Path = CGPath(roundedRect: bubble3Rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.saveGState()
    ctx.addPath(b3Path)
    ctx.setFillColor(NSColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.9).cgColor)
    ctx.fillPath()
    ctx.addPath(b3Path)
    ctx.setStrokeColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.45).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    NSAttributedString(string: "◉ [You] · 14:02:30 · Mic Tap 16kHz", attributes: youMetaAttrs)
        .draw(at: CGPoint(x: bubble3Rect.minX + 16, y: bubble3Rect.maxY - 26))
    
    let text3 = "Yes, Echo unifies both modes under one status-bar binary. Quick dictation pastes at cursor; meeting mode saves structured notes here."
    NSAttributedString(string: text3, attributes: bAttrs1)
        .draw(in: CGRect(x: bubble3Rect.minX + 16, y: bubble3Rect.minY + 12, width: bubble3Rect.width - 32, height: 54))
    
    // Right Pane Content (Live AI Notes)
    NSAttributedString(string: "LIVE AI EXECUTIVE NOTES", attributes: leftHeaderAttrs)
        .draw(at: CGPoint(x: rightRect.minX + 24, y: rightRect.maxY - 32))
    
    let cardRect = CGRect(x: rightRect.minX + 24, y: rightRect.maxY - 360, width: rightRect.width - 48, height: 310)
    let cPath = CGPath(roundedRect: cardRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    ctx.saveGState()
    ctx.addPath(cPath)
    ctx.setFillColor(NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.addPath(cPath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let sec1Attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        .foregroundColor: NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
    ]
    NSAttributedString(string: "Key Decisions:", attributes: sec1Attrs)
        .draw(at: CGPoint(x: cardRect.minX + 16, y: cardRect.maxY - 28))
    
    let bulletAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(white: 0.85, alpha: 1.0)
    ]
    NSAttributedString(string: "• Single unified binary selected over 2 separate apps.\n• Phonon-2 INT6 locked as primary speech engine.\n• Non-activating HUD guarantees zero window focus theft.", attributes: bulletAttrs)
        .draw(in: CGRect(x: cardRect.minX + 16, y: cardRect.maxY - 96, width: cardRect.width - 32, height: 60))
    
    let sec2Attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        .foregroundColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0)
    ]
    NSAttributedString(string: "Action Items:", attributes: sec2Attrs)
        .draw(at: CGPoint(x: cardRect.minX + 16, y: cardRect.maxY - 130))
    
    NSAttributedString(string: "[✓] Benchmark Swift loopback engine (0.53s decode)\n[✓] Build floating HUD & push-to-talk hotkey\n[✓] Deploy dual-channel CoreAudio loopback\n[ ] Package production Echo.app bundle", attributes: bulletAttrs)
        .draw(in: CGRect(x: cardRect.minX + 16, y: cardRect.maxY - 220, width: cardRect.width - 32, height: 80))
    
    // Export button
    let btnRect = CGRect(x: rightRect.minX + 24, y: cardRect.minY - 56, width: rightRect.width - 48, height: 42)
    let bPath = CGPath(roundedRect: btnRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(bPath)
    ctx.setFillColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    let btnAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    let btnStr = NSAttributedString(string: "Export Notes to Obsidian (.md)", attributes: btnAttrs)
    let bSize = btnStr.size()
    btnStr.draw(at: CGPoint(x: btnRect.midX - bSize.width / 2, y: btnRect.midY - bSize.height / 2))
    
    img.unlockFocus()
    return img
}

func renderUIOptionB(width: CGFloat = 960, height: CGFloat = 580) -> NSImage {
    let (img, ctx, contentRect) = createBaseWindow(width: width, height: height, title: "Echo Atelier Studio — Acoustic Review", statusRight: "● REC 08:32", statusColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0))
    
    // Pure Obsidian Dark Background
    ctx.setFillColor(NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0).cgColor)
    ctx.fill(contentRect)
    
    // Floating Pill HUD
    let hudRect = CGRect(x: contentRect.minX + 40, y: contentRect.maxY - 64, width: contentRect.width - 80, height: 44)
    let hPath = CGPath(roundedRect: hudRect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.saveGState()
    ctx.addPath(hPath)
    ctx.setFillColor(NSColor(white: 0.1, alpha: 0.8).cgColor)
    ctx.fillPath()
    ctx.addPath(hPath)
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 0.35).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let hudTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0)
    ]
    NSAttributedString(string: "ECHO / ACOUSTIC STUDIO", attributes: hudTitleAttrs)
        .draw(at: CGPoint(x: hudRect.minX + 24, y: hudRect.midY - 7))
    
    let hudItemsAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor(white: 0.85, alpha: 1.0)
    ]
    NSAttributedString(string: "MIC [440Hz]   |   SPEAKER [LOOP]   |   VAD 600ms", attributes: hudItemsAttrs)
        .draw(at: CGPoint(x: hudRect.maxX - 320, y: hudRect.midY - 7))
    
    // Editorial Quote 1
    let quote1Y: CGFloat = contentRect.maxY - 170
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(red: 0.90, green: 0.66, blue: 0.24, alpha: 1.0).cgColor)
    ctx.setLineWidth(3)
    ctx.strokeLineSegments(between: [
        CGPoint(x: contentRect.minX + 50, y: quote1Y + 50),
        CGPoint(x: contentRect.minX + 50, y: quote1Y - 10)
    ])
    ctx.restoreGState()
    
    let quoteAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 17, weight: .light),
        .foregroundColor: NSColor.white
    ]
    let q1Text = "\"We have benchmarked the Phonon-2 speech engine on Apple Silicon. The INT6 quantization runs under 600MB RAM with zero silence hallucinations.\""
    NSAttributedString(string: q1Text, attributes: quoteAttrs)
        .draw(in: CGRect(x: contentRect.minX + 70, y: quote1Y - 8, width: contentRect.width - 140, height: 60))
    
    let metaAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor(white: 0.5, alpha: 1.0)
    ]
    NSAttributedString(string: "UTTERANCE 01 · SPEAKER: YOU · CONFIDENCE 99.4% · 14:02:15", attributes: metaAttrs)
        .draw(at: CGPoint(x: contentRect.minX + 70, y: quote1Y - 26))
    
    // Editorial Quote 2
    let quote2Y: CGFloat = quote1Y - 140
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(white: 0.4, alpha: 1.0).cgColor)
    ctx.setLineWidth(3)
    ctx.strokeLineSegments(between: [
        CGPoint(x: contentRect.minX + 50, y: quote2Y + 50),
        CGPoint(x: contentRect.minX + 50, y: quote2Y - 10)
    ])
    ctx.restoreGState()
    
    let q2Text = "\"That is an enormous speedup over Whisper small. Can we support both push-to-talk cursor dictation and meeting recording in one app?\""
    NSAttributedString(string: q2Text, attributes: quoteAttrs)
        .draw(in: CGRect(x: contentRect.minX + 70, y: quote2Y - 8, width: contentRect.width - 140, height: 60))
    
    NSAttributedString(string: "UTTERANCE 02 · SPEAKER: ATTENDEE · CONFIDENCE 98.7% · 14:02:22", attributes: metaAttrs)
        .draw(at: CGPoint(x: contentRect.minX + 70, y: quote2Y - 26))
    
    img.unlockFocus()
    return img
}

func renderUIOptionC(width: CGFloat = 960, height: CGFloat = 580) -> NSImage {
    let (img, ctx, contentRect) = createBaseWindow(width: width, height: height, title: "TERMINAL // ECHO_AUDIO_CORE_v1.0", statusRight: "SYS:ACTIVE", statusColor: NSColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1.0))
    
    ctx.setFillColor(NSColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1.0).cgColor)
    ctx.fill(contentRect)
    
    // Telemetry Top Bento Cards
    let cardW = (contentRect.width - 64) / 3
    let bentoY = contentRect.maxY - 110
    
    let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let emeraldColor = NSColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1.0)
    
    for i in 0..<3 {
        let bRect = CGRect(x: contentRect.minX + 24 + CGFloat(i) * (cardW + 8), y: bentoY, width: cardW, height: 86)
        let bPath = CGPath(roundedRect: bRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.saveGState()
        ctx.addPath(bPath)
        ctx.setFillColor(NSColor(red: 0.06, green: 0.09, blue: 0.12, alpha: 0.9).cgColor)
        ctx.fillPath()
        ctx.addPath(bPath)
        ctx.setStrokeColor(emeraldColor.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
        
        let tAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: emeraldColor
        ]
        let txt: String
        switch i {
        case 0: txt = "ENGINE: PHONON-2\nARCH: INT6 QUANT (MLX)\nTHREADS: 4 NEON-I8MM"
        case 1: txt = "STREAM: 16000 HZ MONO\nVAD SENS: 0.08 RMS\nLOOPBACK: SCSTREAM_OK"
        default: txt = "SPEED: 37.7X REALTIME\nDECODE: 0.53s / 20.0s\nZERO_HALLUCINATION: TRUE"
        }
        NSAttributedString(string: txt, attributes: tAttrs)
            .draw(in: CGRect(x: bRect.minX + 12, y: bRect.minY + 12, width: bRect.width - 24, height: 62))
    }
    
    // Oscilloscope Radar Box
    let oscRect = CGRect(x: contentRect.minX + 24, y: bentoY - 140, width: contentRect.width - 48, height: 120)
    let oPath = CGPath(roundedRect: oscRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(oPath)
    ctx.setFillColor(emeraldColor.withAlphaComponent(0.04).cgColor)
    ctx.fillPath()
    ctx.addPath(oPath)
    ctx.setStrokeColor(emeraldColor.withAlphaComponent(0.4).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    
    // Draw synthetic green waveform
    let wavePath = CGMutablePath()
    wavePath.move(to: CGPoint(x: oscRect.minX + 20, y: oscRect.midY))
    for x in stride(from: 20, to: Int(oscRect.width - 20), by: 10) {
        let fx = CGFloat(x)
        let amp = sin(fx * 0.05) * 35.0 * sin(fx * 0.015)
        wavePath.addLine(to: CGPoint(x: oscRect.minX + fx, y: oscRect.midY + amp))
    }
    ctx.addPath(wavePath)
    ctx.setStrokeColor(emeraldColor.cgColor)
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Terminal Log Stream
    let logY = oscRect.minY - 140
    let logAttrs: [NSAttributedString.Key: Any] = [
        .font: monoFont,
        .foregroundColor: NSColor(white: 0.85, alpha: 1.0)
    ]
    let logStr = """
    [14:02:15.102] <YOU:MIC> We have benchmarked the Phonon-2 engine on Apple Silicon.
    [14:02:22.450] <REMOTE:SCK> That is an enormous speedup over Whisper small.
    [14:02:30.812] <YOU:MIC> Echo unifies both modes under one menu bar item.
    [14:02:35.000] [AUDIO_CORE] VAD silence detected (600ms) -> Utterance committed to database.
    """
    NSAttributedString(string: logStr, attributes: logAttrs)
        .draw(in: CGRect(x: contentRect.minX + 28, y: logY, width: contentRect.width - 56, height: 120))
    
    img.unlockFocus()
    return img
}

func renderMenuBarMockup(width: CGFloat = 960, height: CGFloat = 240) -> NSImage {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    
    // Background canvas
    ctx.setFillColor(NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    let barH: CGFloat = 40
    let barY1: CGFloat = height - 70
    let barY2: CGFloat = barY1 - 80
    
    // Mockup 1: Minimal Glyph
    let bar1Rect = CGRect(x: 30, y: barY1, width: width - 60, height: barH)
    let p1 = CGPath(roundedRect: bar1Rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(p1)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.addPath(p1)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    let boldFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    let wAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let bAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: NSColor.white]
    
    NSAttributedString(string: "   File   Edit   View   Window   Help", attributes: wAttrs)
        .draw(at: CGPoint(x: bar1Rect.minX + 16, y: bar1Rect.midY - 8))
    
    // Right items
    let echoIdleAttrs: [NSAttributedString.Key: Any] = [
        .font: boldFont,
        .foregroundColor: NSColor(white: 0.9, alpha: 1.0)
    ]
    NSAttributedString(string: "◉", attributes: echoIdleAttrs)
        .draw(at: CGPoint(x: bar1Rect.maxX - 160, y: bar1Rect.midY - 8))
    
    let sysAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.7, alpha: 1.0)]
    NSAttributedString(string: "  Wi-Fi   100%   Mon 14:02", attributes: sysAttrs)
        .draw(at: CGPoint(x: bar1Rect.maxX - 145, y: bar1Rect.midY - 8))
    
    let label1Attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
    ]
    NSAttributedString(string: "VARIANT 1: MINIMAL GLYPH ONLY [◉] (IDLE)", attributes: label1Attrs)
        .draw(at: CGPoint(x: 30, y: barY1 + 46))
    
    // Mockup 2: Meeting Recording State (with pill)
    let bar2Rect = CGRect(x: 30, y: barY2, width: width - 60, height: barH)
    let p2 = CGPath(roundedRect: bar2Rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.addPath(p2)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.addPath(p2)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    NSAttributedString(string: "   File   Edit   View   Window   Help", attributes: wAttrs)
        .draw(at: CGPoint(x: bar2Rect.minX + 16, y: bar2Rect.midY - 8))
    
    // Active Recording Pill in Menu Bar
    let pillRect = CGRect(x: bar2Rect.maxX - 235, y: bar2Rect.midY - 12, width: 84, height: 24)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.setFillColor(NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.2).cgColor)
    ctx.fillPath()
    ctx.addPath(pillPath)
    ctx.setStrokeColor(NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.5).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
    
    let recAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
    ]
    NSAttributedString(string: "● 14:02", attributes: recAttrs)
        .draw(at: CGPoint(x: pillRect.minX + 10, y: pillRect.midY - 7))
    
    NSAttributedString(string: "  Wi-Fi   100%   Mon 14:02", attributes: sysAttrs)
        .draw(at: CGPoint(x: bar2Rect.maxX - 145, y: bar2Rect.midY - 8))
    
    let label2Attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
    ]
    NSAttributedString(string: "VARIANT 2: GLYPH + DURATION PILL [● 14:02] (MEETING RECORDING)", attributes: label2Attrs)
        .draw(at: CGPoint(x: 30, y: barY2 + 46))
    
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

let uiA = renderUIOptionA()
let uiB = renderUIOptionB()
let uiC = renderUIOptionC()
let menuBar = renderMenuBarMockup()

savePNG(image: uiA, path: "\(artifactDir)/echo_ui_option_a_bento.png")
savePNG(image: uiB, path: "\(artifactDir)/echo_ui_option_b_swiss.png")
savePNG(image: uiC, path: "\(artifactDir)/echo_ui_option_c_cyber.png")
savePNG(image: menuBar, path: "\(artifactDir)/echo_menubar_mockups.png")

savePNG(image: uiA, path: "\(devDocsDir)/echo_ui_option_a_bento.png")
savePNG(image: uiB, path: "\(devDocsDir)/echo_ui_option_b_swiss.png")
savePNG(image: uiC, path: "\(devDocsDir)/echo_ui_option_c_cyber.png")
savePNG(image: menuBar, path: "\(devDocsDir)/echo_menubar_mockups.png")
