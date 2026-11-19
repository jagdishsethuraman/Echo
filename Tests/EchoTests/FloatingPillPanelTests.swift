import AppKit
import Testing
@testable import Echo

@Suite("FloatingPillPanel", .serialized)
struct FloatingPillPanelTests {
    
    @Test func measureTextWidthHandlesEmptyAndNonEmptyStrings() {
        #expect(FloatingPillPanel.measureTextWidth("") == 0)
        
        let latinWidth = FloatingPillPanel.measureTextWidth("Hello World")
        #expect(latinWidth > 50 && latinWidth < 100)
        
        // CJK characters have wider typographic bounding box
        let cjkWidth = FloatingPillPanel.measureTextWidth("语音输入听写系统")
        #expect(cjkWidth > latinWidth)
    }
    
    @Test func targetWidthDefaultsForFixedStates() {
        #expect(FloatingPillPanel.targetWidth(for: .idle) == 240)
        #expect(FloatingPillPanel.targetWidth(for: .transcribing) == 280)
        #expect(FloatingPillPanel.targetWidth(for: .error(message: "Failed")) == 360)
    }
    
    @Test func targetWidthExpandsWithTypographicContent() {
        let baseListening = FloatingPillPanel.targetWidth(for: .listening(audioLevel: 0.2, livePartial: "", isLocked: false, elapsedSeconds: 5))
        #expect(baseListening == 370)
        
        let lockedListening = FloatingPillPanel.targetWidth(for: .listening(audioLevel: 0.2, livePartial: "", isLocked: true, elapsedSeconds: 5))
        #expect(lockedListening == 410)
        
        // A long utterance expands the pill beyond minimum width
        let longText = "This is a long transcribed sentence describing our architectural decisions and database schema."
        let expanded = FloatingPillPanel.targetWidth(for: .listening(audioLevel: 0.3, livePartial: longText, isLocked: false, elapsedSeconds: 10))
        #expect(expanded > baseListening)
        #expect(expanded <= 720)
        
        // Quantization check: width must be a multiple of 30
        #expect(Int(expanded) % 30 == 0)
    }
    
    @Test func targetWidthForSuccessAdaptsToPreview() {
        let shortSuccess = FloatingPillPanel.targetWidth(for: .success(preview: "Done"))
        #expect(shortSuccess >= 280 && shortSuccess <= 300)
        #expect(Int(shortSuccess) % 30 == 0)
        
        let longSuccess = FloatingPillPanel.targetWidth(for: .success(preview: "Successfully transcribed 45 minutes of meeting discussion without audio dropped."))
        #expect(longSuccess > shortSuccess)
        #expect(longSuccess <= 720)
        #expect(Int(longSuccess) % 30 == 0)
    }
}
