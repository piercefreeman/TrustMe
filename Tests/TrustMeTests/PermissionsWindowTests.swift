import AppKit
import Testing
@testable import TrustMe

/// A permission whose status the test sets. Each gets its own id, so
/// ``PermissionCenter``'s cache never carries one test's answer into another.
@MainActor
func testPermission(_ name: String, _ state: StatusSwitch) -> Permission {
    Permission(id: "test-\(name)-\(UUID().uuidString)", title: name, summary: "For tests", systemImage: "star",
               tint: .red, settingsAnchor: "Privacy_Test") { state.status }
}

@Suite("Permissions window", .serialized)
@MainActor
struct PermissionsWindowTests {
    final class Finishes { var calls: [Bool] = [] }

    func show(_ permissions: [Permission], optional: Set<Permission> = []) async -> (PermissionsWindow, Finishes) {
        _ = NSApplication.shared
        let finishes = Finishes()
        let window = PermissionsWindow.show(permissions, optional: optional) { finishes.calls.append($0) }
        _ = await eventually(timeout: 1) { window.window.isVisible }
        return (window, finishes)
    }

    /// Return, as typed: Continue is the window's default button.
    func pressReturn(in window: NSWindow) async {
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, characters: "\r",
                                          charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        _ = await eventually(timeout: 0.3) { !window.isVisible }
    }

    /// Flips a status the way the app sees it change, and lets the view catch up.
    func grant(_ state: StatusSwitch) async {
        state.status = .granted
        PermissionCenter.shared.refresh()
        _ = await eventually(timeout: 0.3) { false }
    }

    @Test("Shows on screen as the current window")
    func shows() async {
        let (window, _) = await show([testPermission("A", StatusSwitch(.notGranted))])
        defer { window.close() }
        #expect(window.window.isVisible)
        #expect(PermissionsWindow.current === window)
    }

    @Test("Continue stays locked while a required permission is missing")
    func locked() async {
        let a = StatusSwitch(.granted), b = StatusSwitch(.notGranted)
        let (window, finishes) = await show([testPermission("A", a), testPermission("B", b)])
        defer { window.close() }
        await pressReturn(in: window.window)
        #expect(window.window.isVisible)
        #expect(finishes.calls.isEmpty)
    }

    @Test("Continue unlocks as the last grant lands, and reports all granted")
    func unlocks() async {
        let a = StatusSwitch(.notGranted)
        let (window, finishes) = await show([testPermission("A", a)])
        defer { window.close() }
        await grant(a)
        await pressReturn(in: window.window)
        #expect(!window.window.isVisible)
        #expect(finishes.calls == [true])
        #expect(PermissionsWindow.current == nil)
    }

    @Test("Optional permissions don't hold up Continue")
    func optional() async {
        let required = testPermission("Required", StatusSwitch(.granted))
        let extra = testPermission("Extra", StatusSwitch(.notGranted))
        let (window, finishes) = await show([required, extra], optional: [extra])
        defer { window.close() }
        await pressReturn(in: window.window)
        #expect(finishes.calls == [true])
    }

    @Test("Closing reports what's missing, once")
    func closeButton() async throws {
        let (window, finishes) = await show([testPermission("A", StatusSwitch(.notGranted))])
        defer { window.close() }
        let close = try #require(window.window.standardWindowButton(.closeButton))
        close.performClick(nil)
        #expect(await eventually { !window.window.isVisible })
        window.close()
        #expect(finishes.calls == [false])
        #expect(PermissionsWindow.current == nil)
    }

    @Test("Showing another replaces it, finishing the first")
    func replaces() async {
        let (first, firstFinishes) = await show([testPermission("A", StatusSwitch(.notGranted))])
        defer { first.close() }
        let (second, secondFinishes) = await show([testPermission("B", StatusSwitch(.notGranted))])
        defer { second.close() }
        #expect(!first.window.isVisible)
        #expect(firstFinishes.calls == [false])
        #expect(second.window.isVisible)
        #expect(secondFinishes.calls.isEmpty)
        #expect(PermissionsWindow.current === second)
    }
}
