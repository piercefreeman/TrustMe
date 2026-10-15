import AppKit
import SwiftUI
import Testing
@testable import TrustMe

/// A ``PermissionFlow`` whose guide panel is real and on screen, with System
/// Settings, the clock and permission state played by the test.
@MainActor
final class FlowRig {
    var now = Date()
    var settings: CGRect?
    var inFront = true
    var running = true
    var status: PermissionStatus = .notGranted
    private(set) var opened: [URL] = []
    private(set) var granted: [Permission] = []
    private var scheduled: [(at: Date, work: @MainActor () -> Void)] = []
    private(set) var flow: PermissionFlow!

    let screen = NSScreen.screens.first!.visibleFrame

    init() {
        _ = NSApplication.shared
        flow = PermissionFlow(system: .init(
            settingsFrame: { [unowned self] in settings },
            settingsInFront: { [unowned self] in inFront },
            settingsRunning: { [unowned self] in running },
            status: { [unowned self] _ in status },
            open: { [unowned self] in opened.append($0) },
            now: { [unowned self] in now },
            after: { [unowned self] delay, work in scheduled.append((now + delay, work)) },
            runsTimer: false
        ))
        flow.app = AppIdentity(url: URL(fileURLWithPath: "/Applications/TrustMe.app"), name: "TrustMe",
                               icon: NSImage(systemSymbolName: "shield", accessibilityDescription: nil)!)
        flow.activatesAppOnGrant = false
        flow.onGranted = { [unowned self] in granted.append($0) }
    }

    func close() { flow.dismiss() }

    /// A Settings-sized window high enough on screen for the guide to dock below it.
    var settingsUp: CGRect {
        CGRect(x: (screen.midX - 357).rounded(), y: (screen.maxY - 520).rounded(), width: 715, height: 480)
    }

    var panel: GuidePanel? { flow.panel }
    var model: GuideModel? { flow.model }
    var isShowing: Bool { panel?.isVisible == true }

    /// Steps the frame loop at 60fps for `seconds`, running whatever comes due.
    func run(_ seconds: TimeInterval = 1.0 / 60) {
        for _ in 0..<max(1, Int((seconds * 60).rounded())) {
            now += 1.0 / 60
            flow.step()
            let due = scheduled.filter { $0.at <= now }
            scheduled.removeAll { $0.at <= now }
            due.forEach { $0.work() }
        }
    }

    var hasScheduled: Bool { !scheduled.isEmpty }

    /// At `origin`, give or take the window server snapping it to whole points.
    func isAt(_ origin: CGPoint) -> Bool {
        guard let frame = panel?.frame else { return false }
        return abs(frame.minX - origin.x) <= 0.5 && abs(frame.minY - origin.y) <= 0.5
    }

    /// Where the guide belongs beside the current Settings frame.
    var expected: (CGPoint, GuideEdge) {
        GuidePlacement.place(panelSize: panel!.frame.size, beside: settings!)
    }

    /// Up and showing beside Settings, as after a normal open.
    func present(_ permission: Permission = .accessibility) {
        flow.authorize(permission)
        settings = settingsUp
        run(0.5)
    }
}

@Suite("Guide panel", .serialized)
@MainActor
struct GuideFlowTests {
    // MARK: Appearing

    @Test("Opens the permission's pane and waits for Settings")
    func opensPane() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.flow.authorize(.accessibility)
        #expect(rig.opened == [Permission.accessibility.settingsURL])
        #expect(rig.flow.activePermission == .accessibility)
        rig.run(1)
        #expect(rig.panel != nil)
        #expect(!rig.isShowing)
    }

    @Test("Appears beside Settings only once it holds still")
    func appearsWhenStill() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.flow.authorize(.accessibility)
        rig.settings = rig.settingsUp
        rig.run(0.25)
        #expect(!rig.isShowing, "Settings hasn't held still long enough")
        rig.run(0.1)
        #expect(rig.isShowing)
        #expect(rig.model?.isPresented == true)
        let (origin, edge) = rig.expected
        #expect(rig.isAt(origin))
        #expect(edge == .below)
        #expect(rig.model?.edge == .below)
        #expect(!rig.panel!.frame.intersects(rig.settingsUp))
    }

    @Test("Doesn't chase Settings while it launches and resizes")
    func waitsForStill() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.flow.authorize(.accessibility)
        for step in 0..<40 {
            rig.settings = rig.settingsUp.insetBy(dx: CGFloat(step), dy: 0)
            rig.run()
        }
        #expect(!rig.isShowing)
    }

    @Test("Waits for Settings to come to the front")
    func waitsForFront() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.flow.authorize(.accessibility)
        rig.inFront = false
        rig.settings = rig.settingsUp
        rig.run(1)
        #expect(!rig.isShowing)
        rig.inFront = true
        rig.run(0.5)
        #expect(rig.isShowing)
    }

    // MARK: While it's up

    @Test("Follows Settings, and turns to point at it")
    func follows() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        // No room below any more: it moves to a side.
        rig.settings = CGRect(x: rig.screen.minX + 20, y: rig.screen.minY + 10,
                              width: 715, height: rig.screen.height - 20)
        rig.run()
        let (origin, edge) = rig.expected
        #expect(edge == .right)
        #expect(rig.isAt(origin))
        #expect(rig.model?.edge == .right)
        #expect(rig.model?.caption.contains("to the left") == true)
        #expect(!rig.panel!.frame.intersects(rig.settings!))
    }

    @Test("Hides while another app is in front, and comes back with Settings")
    func hidesBehindOtherApps() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        rig.inFront = false
        rig.run()
        #expect(!rig.isShowing)
        #expect(rig.flow.activePermission == .accessibility)
        rig.inFront = true
        rig.run()
        #expect(rig.isShowing)
    }

    @Test("Stays up mid-drag, when Settings isn't the active app")
    func staysUpWhileDragging() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        rig.model?.dragBegan()
        rig.inFront = false
        rig.run(0.5)
        #expect(rig.isShowing)
    }

    @Test("Hides when Settings is minimized, and comes back with it")
    func settingsMinimized() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        rig.settings = nil
        rig.run(0.5)
        #expect(rig.isShowing, "A brief gap, e.g. while Settings navigates, isn't enough")
        rig.run(0.2)
        #expect(!rig.isShowing)
        #expect(rig.flow.activePermission == .accessibility)

        rig.settings = rig.settingsUp
        rig.run()
        #expect(rig.isShowing)
    }

    @Test("Closes once Settings quits")
    func settingsQuit() async {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        let panel = rig.panel
        rig.settings = nil
        rig.running = false
        rig.run(0.5)
        #expect(rig.flow.activePermission == .accessibility)
        rig.run(0.2)
        #expect(rig.flow.activePermission == nil)
        #expect(await eventually { panel?.isVisible == false })
    }

    // MARK: Granted

    @Test("Shows the grant, then closes")
    func granted() async {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        let panel = rig.panel
        rig.status = .granted
        rig.run(0.4)
        #expect(rig.model?.phase == .granted)
        #expect(rig.granted == [.accessibility])
        #expect(rig.isShowing, "Lingers to show the check mark")

        rig.run(1.5)
        #expect(rig.flow.activePermission == nil)
        #expect(await eventually { panel?.isVisible == false })
        #expect(rig.granted == [.accessibility], "Reported once")
    }

    @Test("Stays up after a grant when asked to")
    func grantedStaysUp() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.flow.dismissesOnGrant = false
        rig.present()
        rig.status = .granted
        rig.run(3)
        #expect(rig.model?.phase == .granted)
        #expect(rig.isShowing)
        #expect(!rig.hasScheduled)
    }

    @Test("Waits for a relaunch with the guide still up")
    func needsRelaunch() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present(.screenRecording)
        rig.status = .needsRelaunch
        rig.run(3)
        #expect(rig.model?.phase == .needsRelaunch)
        #expect(rig.model?.caption == "Allowed. Relaunch to apply it.")
        #expect(rig.isShowing)
        #expect(rig.granted == [.screenRecording], "Reported once")
        #expect(!rig.hasScheduled)
    }

    // MARK: Closing

    @Test("Close hides the panel and ends the flow")
    func dismiss() async {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present()
        let panel = rig.panel
        rig.model?.onClose()
        #expect(rig.flow.activePermission == nil)
        #expect(rig.panel == nil)
        #expect(await eventually { panel?.isVisible == false })
    }

    @Test("Asking for another permission replaces the guide")
    func replaces() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present(.accessibility)
        let first = rig.panel
        rig.flow.authorize(.screenRecording)
        #expect(first?.isVisible == false, "Gone at once, not faded")
        #expect(rig.flow.activePermission == .screenRecording)
        #expect(rig.model?.permission == .screenRecording)
    }

    @Test("A close due from an earlier grant leaves a newer guide up")
    func staleClose() {
        let rig = FlowRig()
        defer { rig.close() }
        rig.present(.accessibility)
        rig.status = .granted
        rig.run(0.4)
        #expect(rig.hasScheduled)

        rig.status = .notGranted
        rig.present(.screenRecording)
        rig.run(1.5)
        #expect(!rig.hasScheduled)
        #expect(rig.flow.activePermission == .screenRecording)
        #expect(rig.isShowing)
    }
}

// MARK: - Dragging

@Suite("Drag phases", .serialized)
@MainActor
struct DragPhaseTests {
    let app = AppIdentity(url: URL(fileURLWithPath: "/Applications/TrustMe.app"), name: "TrustMe",
                          icon: NSImage(systemSymbolName: "shield", accessibilityDescription: nil)!)

    /// A model whose delayed work waits for the test to run it.
    func model() -> (GuideModel, () -> Void) {
        let model = GuideModel(permission: .accessibility, app: app)
        var pending: [(TimeInterval, @MainActor () -> Void)] = []
        model.after = { pending.append(($0, $1)) }
        return (model, {
            #expect(pending.allSatisfy { $0.0 == GuideModel.stallDelay })
            pending.forEach { $0.1() }
            pending = []
        })
    }

    @Test("A cancelled drag goes back to waiting")
    func cancelled() {
        let (model, later) = model()
        model.dragBegan()
        #expect(model.phase == .dragging)
        model.dragEnded(dropped: false)
        #expect(model.phase == .waiting)
        later()
        #expect(model.phase == .waiting)
    }

    @Test("A drop waits for approval, then suggests a fix if the grant never comes")
    func stalls() {
        let (model, later) = model()
        model.dragBegan()
        model.dragEnded(dropped: true)
        #expect(model.phase == .dropped)
        #expect(model.caption == "Approve with Touch ID or your password")
        later()
        #expect(model.phase == .stalled)
    }

    @Test("A grant that lands in time isn't marked stalled")
    func grantedInTime() {
        let (model, later) = model()
        model.dragBegan()
        model.dragEnded(dropped: true)
        model.phase = .granted
        later()
        #expect(model.phase == .granted)
    }

    @Test("A drag that ends after the phase moved on is ignored")
    func lateEnd() {
        let (model, later) = model()
        model.dragBegan()
        model.phase = .granted
        model.dragEnded(dropped: false)
        #expect(model.phase == .granted)
        later()
        #expect(model.phase == .granted)
    }

    // MARK: The real view

    /// The guide band in a real window, with its drag source laid out.
    func hosted(_ model: GuideModel) async -> (NSWindow, AppDragSourceView)? {
        _ = NSApplication.shared
        model.isPresented = true
        let hosting = NSHostingView(rootView: DragGuideView(model: model))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 200, y: 200), size: hosting.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        var source: AppDragSourceView?
        _ = await eventually(timeout: 1) {
            window.contentView?.layoutSubtreeIfNeeded()
            source = window.contentView.flatMap(Self.find)
            // Laid out, and what a click at its middle actually lands on.
            guard let source, let content = window.contentView, !source.bounds.isEmpty else { return false }
            let middle = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil)
            return content.hitTest(content.superview?.convert(middle, from: nil) ?? middle) === source
        }
        return source.map { (window, $0) }
    }

    static func find(in view: NSView) -> AppDragSourceView? {
        view as? AppDragSourceView ?? view.subviews.lazy.compactMap(find).first
    }

    /// A real mouse event, hit-tested by the window as AppKit routes a click.
    func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) {
        window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 1)!)
    }

    @Test("The band presses under a real click, and a twitch isn't a drag")
    func press() async throws {
        let (model, _) = model()
        let (window, source) = try #require(await hosted(model))
        defer { window.orderOut(nil) }
        #expect(source.appURL == app.url)
        let center = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil)

        mouse(.leftMouseDown, at: center, in: window)
        #expect(model.isPressed)
        mouse(.leftMouseDragged, at: CGPoint(x: center.x + 2, y: center.y), in: window)
        #expect(model.phase == .waiting, "Under the drag threshold")
        mouse(.leftMouseUp, at: center, in: window)
        #expect(!model.isPressed)
    }

    @Test("The view's drag callbacks drive the model")
    func wiring() async throws {
        let (model, later) = model()
        let (window, source) = try #require(await hosted(model))
        defer { window.orderOut(nil) }
        source.onDragBegan()
        #expect(model.phase == .dragging)
        source.onDragEnded(true)
        #expect(model.phase == .dropped)
        later()
        #expect(model.phase == .stalled)
    }

    @Test("No drag source once it's allowed")
    func noDragWhenAllowed() async {
        let (model, _) = model()
        model.phase = .granted
        #expect(await hosted(model) == nil)
    }
}
