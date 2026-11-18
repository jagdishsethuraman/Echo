#if DEBUG
import SwiftUI

/// Sample data used by Xcode canvas previews while iterating on the UI.
public enum StudioPreviewData {
    public static let session: MeetingSession = {
        let base = Date()
        return MeetingSession(
            title: "Weekly Product Sync",
            startTime: base,
            segments: [
                TranscriptSegment(
                    speaker: .you,
                    timestamp: base,
                    text: "Let's start with the launch checklist — the studio redesign should land before the beta cut.",
                    durationSeconds: 4.2
                ),
                TranscriptSegment(
                    speaker: .meeting,
                    timestamp: base.addingTimeInterval(21),
                    text: "Agreed. The frosted window chrome looks much closer to a native macOS app now.",
                    durationSeconds: 3.1
                ),
                TranscriptSegment(
                    speaker: .you,
                    timestamp: base.addingTimeInterval(57),
                    text: "And the transcript rail should stay neutral so the speaker colors carry the meaning.",
                    durationSeconds: 2.8
                ),
                TranscriptSegment(
                    speaker: .meeting,
                    timestamp: base.addingTimeInterval(94),
                    text: "I'll update the design tokens and send a build for review this afternoon.",
                    durationSeconds: 2.5
                )
            ]
        )
    }()
}

#Preview("Meeting Studio") {
    MeetingStudioView(
        session: StudioPreviewData.session,
        micLevel: 0.42,
        systemLevel: 0.68,
        isRecording: true
    )
    .frame(width: 900, height: 620)
    .preferredColorScheme(.dark)
}

#Preview("Listening Pill") {
    FloatingPillView(
        state: .listening(
            audioLevel: 0.55,
            livePartial: "We should ship the frosted",
            isLocked: true,
            elapsedSeconds: 74
        )
    )
    .padding(24)
    .background(Color.black.opacity(0.6))
    .preferredColorScheme(.dark)
}
#endif
