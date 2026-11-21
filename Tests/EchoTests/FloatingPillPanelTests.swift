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
    
    @Test func listeningWidthStaysStableAcrossPreviewAndLockChanges() {
        let width = FloatingPillPanel.targetWidth(for: .listening(audioLevel: 0))
        for text in ["", "Hello, hello.", String(repeating: "Many more words ", count: 30)] {
            for locked in [false, true] {
                let state = PillState.listening(audioLevel: 1, livePartial: text, isLocked: locked, elapsedSeconds: 599)
                #expect(FloatingPillPanel.targetWidth(for: state) == width)
            }
        }
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
