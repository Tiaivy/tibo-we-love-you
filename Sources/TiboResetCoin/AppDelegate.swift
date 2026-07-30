import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = MonitorService()
    private let alertWindow = AlertWindowController()
    private let checkStatusWindow = CheckStatusWindowController()

    private var statusItem: NSStatusItem!
    private let launchAtLoginMenuItem = NSMenuItem(
        title: "Launch at login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        bindMonitor()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = makeStatusIcon(description: "Tibo, We Love You")
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Tibo, We Love You")
            button.toolTip = "Tibo, We Love You"
        }

        launchAtLoginMenuItem.state =
            SMAppService.mainApp.status == .enabled ? .on : .off

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Check now",
            action: #selector(checkNow),
            keyEquivalent: "r"
        )
        menu.addItem(
            withTitle: "Test button animation",
            action: #selector(testAnimation),
            keyEquivalent: "t"
        )
        menu.addItem(.separator())
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(
            withTitle: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
    }

    private func bindMonitor() {
        monitor.onStateChange = { [weak self] state in
            self?.updateStatusIcon(for: state)
        }
        monitor.onAlert = { [weak self] alert in
            guard let self else { return }
            self.checkStatusWindow.close(animated: false)
            self.alertWindow.show(
                alert,
                on: self.statusItem.button?.window?.screen
            )
            self.flashStatusIcon()
        }
        monitor.onCheckStatus = { [weak self] lastResetAt in
            guard let self, !self.alertWindow.isVisible else { return }
            self.checkStatusWindow.show(
                lastResetAt: lastResetAt,
                on: self.statusItem.button?.window?.screen
            )
        }
    }

    private func updateStatusIcon(for state: MonitorState) {
        statusItem.button?.image = makeStatusIcon(description: state.menuText)
        statusItem.button?.setAccessibilityLabel(state.menuText)
    }

    private func flashStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = makeStatusIcon(
            isPressed: true,
            description: "Limits reset detected"
        )
        button.setAccessibilityLabel("Limits reset detected")

        Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            updateStatusIcon(for: monitor.state)
        }
    }

    private func makeStatusIcon(
        isPressed: Bool = false,
        description: String
    ) -> NSImage {
        let renderer = ImageRenderer(
            content: MenuBarButtonIcon(isPressed: isPressed)
                .frame(width: 22, height: 22)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let cgImage = renderer.cgImage else {
            return NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: description
            ) ?? NSImage(size: NSSize(width: 22, height: 22))
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: 22, height: 22)
        )
        image.isTemplate = false
        return image
    }

    @objc private func checkNow() {
        Task { await monitor.checkNow(showStatus: true) }
    }

    @objc private func testAnimation() {
        monitor.testAlert()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginMenuItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginMenuItem.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Unable to update launch-at-login setting"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct MenuBarButtonIcon: View {
    let isPressed: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let pressOffset = isPressed ? size * 0.09 : 0

            ZStack {
                Ellipse()
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.10))
                    .frame(width: size * 0.92, height: size * 0.36)
                    .offset(y: size * 0.25)

                Ellipse()
                    .fill(Color(red: 0.25, green: 0.27, blue: 0.29))
                    .frame(width: size * 0.82, height: size * 0.28)
                    .offset(y: size * 0.15)

                RoundedRectangle(
                    cornerRadius: size * 0.12,
                    style: .continuous
                )
                    .fill(Color(red: 0.72, green: 0.03, blue: 0.05))
                    .frame(
                        width: size * 0.60,
                        height: size * (isPressed ? 0.28 : 0.38)
                    )
                    .offset(y: pressOffset - size * 0.02)

                Ellipse()
                    .fill(Color(red: 0.96, green: 0.06, blue: 0.08))
                    .frame(width: size * 0.60, height: size * 0.27)
                    .offset(y: pressOffset - size * 0.19)

                Ellipse()
                    .stroke(
                        Color.white.opacity(0.42),
                        lineWidth: max(0.7, size * 0.035)
                    )
                    .frame(width: size * 0.51, height: size * 0.16)
                    .offset(y: pressOffset - size * 0.20)
            }
            .frame(width: size, height: size)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
        }
    }
}
