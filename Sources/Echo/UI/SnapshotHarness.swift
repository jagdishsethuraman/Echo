#if DEBUG
import AppKit
import SwiftUI

/// Offscreen snapshot harness used while iterating on the visual design.
/// Run with `Echo --snapshot <directory>` to write PNGs of the main surfaces.
@MainActor
enum SnapshotHarness {
    static func renderIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot") else {
            return false
        }
        let directory = index + 1 < CommandLine.arguments.count
            ? CommandLine.arguments[index + 1]
            : NSTemporaryDirectory()

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        render(
            studio,
            size: CGSize(width: 900, height: 620),
            to: url.appendingPathComponent("studio.png")
        )
        render(
            pill,
            size: CGSize(width: 440, height: 56),
            to: url.appendingPathComponent("pill.png")
        )
        render(
            emptyStudio,
            size: CGSize(width: 900, height: 620),
            to: url.appendingPathComponent("studio-empty.png")
        )

        render(
            narrowStudio,
            size: CGSize(width: 840, height: 560),
            to: url.appendingPathComponent("studio-narrow.png")
        )

        WordMemoryState.shared.isVisible = true
        render(
            studio,
            size: CGSize(width: 900, height: 620),
            to: url.appendingPathComponent("studio-memory.png")
        )
        WordMemoryState.shared.isVisible = false

        print("Snapshots written to \(url.path)")
        return true
    }

    private static var desktop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.19, blue: 0.24),
                Color(red: 0.09, green: 0.11, blue: 0.15),
                Color(red: 0.20, green: 0.18, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static var studio: some View {
        ZStack {
            desktop
            MeetingStudioView(
                session: StudioPreviewData.session,
                micLevel: 0.42,
                systemLevel: 0.68,
                isRecording: true
            )
            .frame(width: 900, height: 620)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(width: 900, height: 620)
    }

    private static var emptyStudio: some View {
        ZStack {
            desktop
            MeetingStudioView(session: MeetingSession(title: "No active session"))
                .frame(width: 900, height: 620)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(width: 900, height: 620)
    }

    private static var narrowStudio: some View {
        ZStack {
            desktop
            MeetingStudioView(
                session: StudioPreviewData.session,
                micLevel: 0.22,
                systemLevel: 0.10
            )
            .frame(width: 840, height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(width: 840, height: 560)
    }

    private static var pill: some View {
        ZStack {
            desktop
            FloatingPillView(
                state: .listening(
                    audioLevel: 0.55,
                    livePartial: "We should ship the frosted",
                    isLocked: true,
                    elapsedSeconds: 74
                )
            )
            .padding(12)
        }
        .frame(width: 440, height: 56)
    }

    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
#endif
