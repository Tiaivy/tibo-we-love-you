import AppKit
import SwiftUI

@main
struct TiboResetCoinMain {
    @MainActor
    static func main() {
        if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(previewIndex + 1) {
            renderPreview(to: CommandLine.arguments[previewIndex + 1])
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    @MainActor
    private static func renderPreview(to path: String) {
        _ = NSApplication.shared
        let view = CoinAlertView(
            preview: true,
            openTweet: {},
            dismiss: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 342, height: 134)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fputs("Unable to render preview\n", stderr)
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("Unable to encode preview\n", stderr)
            return
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fputs("Unable to save preview: \(error.localizedDescription)\n", stderr)
        }
    }
}
