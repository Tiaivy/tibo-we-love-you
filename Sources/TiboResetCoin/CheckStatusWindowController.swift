import AppKit
import SwiftUI

@MainActor
final class CheckStatusWindowController {
    private var panel: NSPanel?
    private var autoDismissTask: Task<Void, Never>?

    func show(checkedAt: Date?, on screen: NSScreen?) {
        close(animated: false)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 342, height: 124),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .fullScreenAuxiliary
        ]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(
            rootView: CheckStatusView(
                checkedAt: checkedAt,
                now: Date()
            )
        )

        let screenFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let finalOrigin = AlertWindowPlacement.origin(
            panelSize: panel.frame.size,
            visibleFrame: screenFrame
        )
        panel.setFrameOrigin(
            NSPoint(x: finalOrigin.x, y: finalOrigin.y + 5)
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(finalOrigin)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func close(animated: Bool = true) {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        guard let panel else { return }

        guard animated else {
            panel.orderOut(nil)
            self.panel = nil
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(
                NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y + 4)
            )
        }, completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                self?.panel = nil
            }
        })
    }
}

struct CheckStatusView: View {
    let checkedAt: Date?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CheckStatusEmojiGraphic()
                .frame(width: 56, height: 56)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text("Nothing new yet")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        Color(red: 0.07, green: 0.075, blue: 0.085)
                    )

                Text(lastCheckedText)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(
                        Color(red: 0.43, green: 0.46, blue: 0.49)
                    )

                Text(nextCheckText)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(
                        Color(red: 0.43, green: 0.46, blue: 0.49)
                    )

                Text("Next reset? Only God knows.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        Color(red: 0.26, green: 0.28, blue: 0.30)
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 326, height: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color(red: 0.87, green: 0.88, blue: 0.90),
                    lineWidth: 1
                )
        }
        .padding(8)
    }

    private var lastCheckedText: String {
        guard let checkedAt else {
            return "Last check time unavailable"
        }
        let formatted = checkedAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
        return "Last checked · \(formatted)"
    }

    private var nextCheckText: String {
        guard let checkedAt else {
            return "Next check coming shortly"
        }
        let nextCheck = checkedAt.addingTimeInterval(10 * 60)
        guard nextCheck > now else {
            return "Next check coming shortly"
        }
        let formatted = nextCheck.formatted(
            date: .omitted,
            time: .shortened
        )
        return "Next check by \(formatted)"
    }
}

private struct CheckStatusEmojiGraphic: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(2.05)
                .offset(x: size * 0.06)
                .frame(width: size, height: size)
                .clipped()
        }
    }

    private var image: NSImage {
        let packagedURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/CheckStatusEmoji.jpg")

        for case let url? in [
            Bundle.main.url(
                forResource: "CheckStatusEmoji",
                withExtension: "jpg"
            ),
            packagedURL
        ] {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        if let developmentURL = Bundle.module.url(
            forResource: "CheckStatusEmoji",
            withExtension: "jpg"
        ),
        let image = NSImage(contentsOf: developmentURL) {
            return image
        }

        return NSImage(size: NSSize(width: 1, height: 1))
    }
}
