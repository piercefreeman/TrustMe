import AppKit
import Testing
@testable import TrustMe

/// A real on-screen window under a dodge, with System Settings, the clock and
/// permission state played by the test. The dodge's own moves go through the
/// window server, so frames here are what actually ended up on screen.
@MainActor
final class DodgeRig {
    var now = Date()
    /// Where System Settings is, and whether the window is above it; nil when it's closed.
    var settings: (frame: CGRect, isBehind: Bool)?
    var active: Permission?
    var status: PermissionStatus = .notGranted

    let screen: CGRect
    let home: CGRect
    let window: NSWindow
    private(set) var dodge: SettingsDodge!

    /// - Parameter locate: Finds Settings for real; by default the test plays it with ``settings``.
    init(locate: (@MainActor (NSWindow) -> (frame: CGRect, isBehind: Bool)?)? = nil) {
        _ = NSApplication.shared
        screen = NSScreen.screens.first!.visibleFrame
        home = Self.home
        window = NSWindow(contentRect: home, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrame(home, display: true)
        window.orderFrontRegardless()
        dodge = SettingsDodge(window: window, activePermission: { [unowned self] in active },
                              status: { [unowned self] _ in status },
                              settings: locate ?? { [unowned self] _ in settings }, now: { [unowned self] in now })
    }

    func close() {
        dodge.stop()
        window.orderOut(nil)
    }

    /// A real mouse-down, through the app's event dispatch, so it meets the
    /// dodge's event monitor the way a click does.
    func click(_ target: NSWindow) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 40, y: 40), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(event)
    }

    /// Where the window starts: centred on the main screen.
    static var home: CGRect {
        let screen = NSScreen.screens.first!.visibleFrame
        return CGRect(x: (screen.midX - 300).rounded(), y: (screen.midY - 200).rounded(), width: 600, height: 400)
    }

    /// A Settings-sized window over the right half of `home`.
    static func overlapping(_ home: CGRect) -> CGRect {
        CGRect(x: home.midX, y: home.midY - 300, width: 715, height: 600)
    }

    var overlapping: CGRect { Self.overlapping(home) }

    /// Opens a pane with ``SettingsDodge/open(_:)``'s bookkeeping, minus Settings itself.
    func openPane() {
        now += 1
        SettingsDodge.paneOpened = now
    }

    func tick(_ seconds: TimeInterval = SettingsDodge.tick) {
        now += seconds
        dodge.check()
    }

    /// Ticks until Settings has held still past the settle time, as the timer would.
    func settle() {
        tick()
        tick()
        tick()
    }

    var isAside: Bool { window.frame != home }

    func clear(of settings: CGRect) -> Bool { !window.frame.intersects(settings) }
}

@Suite("Settings dodge with real windows", .serialized)
@MainActor
struct SettingsDodgeWindowTests {
    // MARK: A trip to a pane

    @Test("Steps aside once Settings settles under it, and comes back when it closes")
    func paneTrip() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        rig.settings = (rig.overlapping, true)

        rig.tick()
        rig.tick()
        #expect(!rig.isAside, "Settings hasn't held still long enough yet")
        rig.tick()
        #expect(rig.isAside)
        #expect(rig.clear(of: rig.overlapping))
        #expect(rig.window.frame.size == rig.home.size)
        #expect(rig.window.frame.minY == rig.home.minY, "Only moves sideways")

        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == rig.home)
    }

    @Test("Doesn't chase Settings while it launches and resizes")
    func waitsForStill() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        for step in 0..<10 {
            rig.settings = (rig.overlapping.insetBy(dx: CGFloat(step) * 4, dy: 0), true)
            rig.tick()
        }
        #expect(!rig.isAside)
        rig.settle()
        #expect(rig.isAside)
    }

    @Test("Follows Settings when it's moved, and still comes back to where it started")
    func followsSettings() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        rig.settings = (rig.overlapping, true)
        rig.settle()
        let firstAside = rig.window.frame
        #expect(rig.clear(of: rig.overlapping))

        let moved = rig.overlapping.offsetBy(dx: firstAside.minX - rig.overlapping.minX + 100, dy: 0)
        rig.settings = (moved, true)
        rig.settle()
        #expect(rig.window.frame != firstAside)
        #expect(rig.clear(of: moved))

        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == rig.home)
    }

    // MARK: Leaving the window be

    @Test("Stays where the person moved it")
    func movedByHand() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        rig.settings = (rig.overlapping, true)
        rig.settle()
        #expect(rig.isAside)

        let theirs = rig.window.frame.offsetBy(dx: 0, dy: -40)
        rig.window.setFrame(theirs, display: true)
        rig.tick()
        // Settings moves again: the window's place is theirs for this trip.
        let moved = CGRect(origin: CGPoint(x: theirs.minX, y: rig.overlapping.minY), size: rig.overlapping.size)
        rig.settings = (moved, true)
        rig.settle()
        #expect(rig.window.frame == theirs)

        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == theirs)
    }

    @Test("Doesn't come back over a spot the person moved it to as Settings closed")
    func movedThenClosed() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        rig.settings = (rig.overlapping, true)
        rig.settle()

        let theirs = rig.window.frame.offsetBy(dx: 0, dy: -40)
        rig.window.setFrame(theirs, display: true)
        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == theirs)
    }

    @Test("A click while aside leaves it there for the rest of the trip")
    func clickedAside() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.dodge.start()
        rig.openPane()
        rig.settings = (rig.overlapping, true)
        rig.settle()
        let aside = rig.window.frame

        rig.click(rig.window)
        rig.settings = (CGRect(origin: CGPoint(x: aside.minX, y: rig.overlapping.minY), size: rig.overlapping.size), true)
        rig.settle()
        #expect(rig.window.frame == aside)

        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == aside)
    }

    @Test("A click in another window doesn't count")
    func clickedElsewhere() {
        let rig = DodgeRig()
        defer { rig.close() }
        let other = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
                             backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.orderFrontRegardless()
        defer { other.orderOut(nil) }
        rig.dodge.start()
        rig.openPane()
        rig.settings = (rig.overlapping, true)
        rig.settle()

        rig.click(other)
        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == rig.home)
    }

    @Test("A click before it moves (Allow, Open settings) doesn't keep it in the way")
    func clickedBefore() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.dodge.start()
        rig.openPane()
        rig.click(rig.window)
        rig.settings = (rig.overlapping, true)
        rig.settle()
        #expect(rig.isAside)
    }

    @Test("Settings in front of the window, or off to the side, is left alone", arguments: [true, false])
    func nothingToDodge(inFront: Bool) {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        rig.settings = inFront
            ? (rig.overlapping, false)
            : (rig.overlapping.offsetBy(dx: rig.home.width, dy: 0), true)
        rig.settle()
        rig.tick()
        #expect(!rig.isAside)
    }

    @Test("Gives up on a pane trip when Settings never shows up")
    func paneTimesOut() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.openPane()
        rig.tick(SettingsDodge.paneWait + 1)

        rig.settings = (rig.overlapping, true)
        rig.settle()
        #expect(!rig.isAside)
    }

    @Test("Settings opened without a trip is left alone")
    func noTrip() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.settings = (rig.overlapping, true)
        rig.settle()
        rig.tick()
        #expect(!rig.isAside)
    }

    // MARK: A grant

    @Test("Comes back once the permission is granted", arguments: [PermissionStatus.granted, .needsRelaunch])
    func grantTrip(granted: PermissionStatus) {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.active = .accessibility
        rig.settings = (rig.overlapping, true)
        rig.settle()
        #expect(rig.isAside)

        rig.status = granted
        rig.tick()
        #expect(rig.window.frame == rig.home)

        // The guide lingers to show the grant; Settings is still under the window.
        rig.settle()
        rig.tick()
        #expect(rig.window.frame == rig.home)
    }

    @Test("Stays aside when the guide closes without a grant")
    func grantAbandoned() {
        let rig = DodgeRig()
        defer { rig.close() }
        rig.active = .accessibility
        rig.settings = (rig.overlapping, true)
        rig.settle()
        let aside = rig.window.frame

        rig.active = nil
        rig.tick()
        rig.settings = nil
        rig.tick()
        #expect(rig.window.frame == aside)
    }
}
