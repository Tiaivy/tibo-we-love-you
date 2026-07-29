import AppKit
import SwiftUI

@MainActor
final class AlertWindowController {
    private var panel: NSPanel?

    func show(_ alert: CoinAlert, on screen: NSScreen?) {
        close(animated: false)

        let content = CoinAlertView(
            openTweet: { [weak self] in
                NSWorkspace.shared.open(alert.tweet.url)
                self?.close()
            },
            dismiss: { [weak self] in
                self?.close()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 342, height: 134),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: content)

        let screenFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let finalOrigin = AlertWindowPlacement.origin(
            panelSize: panel.frame.size,
            visibleFrame: screenFrame
        )
        panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 8))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            panel.animator().setFrameOrigin(finalOrigin)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func close(animated: Bool = true) {
        guard let panel else { return }

        guard animated else {
            panel.orderOut(nil)
            self.panel = nil
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(
                NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y + 6)
            )
        }, completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                self?.panel = nil
            }
        })
    }
}

enum AlertWindowPlacement {
    static func origin(
        panelSize: NSSize,
        visibleFrame: NSRect,
        horizontalInset: CGFloat = 16,
        topInset: CGFloat = 10
    ) -> NSPoint {
        return NSPoint(
            x: visibleFrame.maxX - panelSize.width - horizontalInset,
            y: visibleFrame.maxY - panelSize.height - topInset
        )
    }
}
