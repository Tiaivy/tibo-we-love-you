import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = MonitorService()
    private let alertWindow = AlertWindowController()

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
            self.alertWindow.show(
                alert,
                on: self.statusItem.button?.window?.screen
            )
            self.flashStatusIcon()
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
            content: ResetButtonGraphic(
                isPressed: isPressed,
                pulseIsVisible: false
            )
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
        Task { await monitor.checkNow() }
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
