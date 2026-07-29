import AppKit
import Testing
@testable import TiboResetCoin

@Test
func placesAlertAtTopRightOfVisibleScreen() {
    let origin = AlertWindowPlacement.origin(
        panelSize: NSSize(width: 342, height: 134),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
    )

    #expect(origin == NSPoint(x: 1082, y: 756))
}

@Test
func placesAlertAtTopRightOfOffsetScreen() {
    let origin = AlertWindowPlacement.origin(
        panelSize: NSSize(width: 342, height: 134),
        visibleFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1080)
    )

    #expect(origin == NSPoint(x: -358, y: 936))
}
