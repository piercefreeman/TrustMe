// Animates TrustMe's onboarding: click Allow, System Settings opens, the glass
// band docks beneath it, and the app is dragged into the Accessibility list.
// Everything is simulated, so it runs the same every time.
//
//   swift run DragDemo              Esc quits, R replays, --once stops after one pass
import AppKit
import DemoSupport
import SwiftUI
@testable import TrustMe

@MainActor
final class Director {
    let state = DemoState()
    let screen = Demo.screen
    let app = AppIdentity(url: Demo.appURL, name: Demo.appName, icon: Demo.appIcon)

    private var backdrop: DemoWindow!
    private var overlay: DemoWindow!
    private var trustWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var authWindow: NSWindow?
    private var band: GuidePanel?
    private var model: GuideModel?
    private var task: Task<Void, Never>?
    private lazy var chip = DragChip.render(app: app)

    /// The screen minus the (fake) menu bar, in AppKit coordinates.
    private var visible: CGRect {
        var frame = screen.frame
        frame.size.height -= Demo.menuBarHeight
        return frame
    }

    func launch() {
        backdrop = DemoWindow(frame: screen.frame, level: Demo.level(0))
        backdrop.contentView = NSHostingView(rootView: DesktopBackdrop(wallpaper: Wallpaper.load(for: screen)))
        backdrop.alphaValue = 0
        backdrop.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; backdrop.animator().alphaValue = 1 }

        overlay = DemoWindow(frame: screen.frame, level: Demo.level(10))
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = true
        overlay.contentView = NSHostingView(rootView: PointerOverlay(state: state, chip: chip))
        overlay.orderFrontRegardless()

        NSCursor.hide()
        Demo.installKeys { [weak self] in self?.start() }
        start()
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            repeat {
                await self.play()
                guard !Task.isCancelled, !Demo.flag("--once") else { return }
                await self.tearDown()
            } while !Task.isCancelled
        }
    }

    // MARK: - The script

    private func play() async {
        clearWindows()
        state.reset()

        let trust = makeTrustWindow()
        let size = trust.frame.size
        trust.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        fadeIn(trust)
        state.cursor = overlayPoint(CGPoint(x: visible.maxX - 220, y: visible.minY + 160))
        withAnimation(.easeOut(duration: 0.3)) { state.cursorVisible = true }
        guard await pause(1.2) else { return }

        // Click Allow on Accessibility.
        let permission = Permission.accessibility
        guard let allow = Anchors.screenRect("allow.\(permission.id)", in: trust) else { return }
        guard await move(to: CGPoint(x: allow.midX, y: allow.midY), duration: 1.0) else { return }
        guard await click(pressing: permission.id) else { return }
        state.activeID = permission.id

        // System Settings opens beside TrustMe.
        guard await pause(0.35) else { return }
        let settings = makeSettingsWindow()
        let gap: CGFloat = 36
        let total = size.width + gap + settings.frame.width
        let left = max(visible.minX + 20, visible.midX - total / 2)
        let settingsX = min(left + size.width + gap, visible.maxX - settings.frame.width - 20)
        settings.setFrameOrigin(CGPoint(x: settingsX, y: visible.maxY - 64 - settings.frame.height))
        slide(trust, to: CGPoint(x: left, y: trust.frame.minY), duration: 0.6)
        guard await pause(0.2) else { return }
        fadeIn(settings)

        // The band docks under the list once Settings has settled.
        guard await pause(1.0) else { return }
        let (band, model) = presentBand(beside: settings.frame)
        guard await pause(1.4) else { return }

        // Pick the app up from the band...
        guard await move(to: CGPoint(x: band.frame.midX + 30, y: band.frame.midY), duration: 1.0) else { return }
        model.isHovering = true
        state.cursorKind = .openHand
        guard await pause(0.5) else { return }
        model.isPressed = true
        state.cursorKind = .closedHand
        guard await pause(0.25) else { return }
        model.isPressed = false
        model.phase = .dragging
        state.cursorKind = .arrow
        withAnimation(.easeOut(duration: 0.15)) { state.chipVisible = true }

        // ...and carry it into the list.
        guard let list = Anchors.screenRect("settings.list", in: settings) else { return }
        let drop = CGPoint(x: list.midX - 40, y: list.minY + 36)
        let travel = 1.3
        let arrive = Task { @MainActor [state] in
            try? await Task.sleep(for: .seconds(travel * 0.72))
            state.dropTargeted = true
            state.cursorKind = .dragCopy
        }
        guard await move(to: drop, duration: travel) else { arrive.cancel(); return }
        guard await pause(0.45) else { return }

        // Drop: System Settings asks for Touch ID.
        withAnimation(.easeIn(duration: 0.15)) { state.chipVisible = false }
        state.dropTargeted = false
        state.cursorKind = .arrow
        model.isHovering = false
        model.phase = .dropped
        guard await pause(0.6) else { return }
        let auth = presentAuth(over: settings.frame)
        guard await pause(1.6) else { return }
        state.touchAccepted = true
        guard await pause(0.5) else { return }
        fadeOut(auth)

        // The app lands in the list and switches on.
        guard await pause(0.3) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            state.listApps.append(.init(name: app.name, icon: app.icon, enabled: false))
        }
        guard await pause(0.45) else { return }
        state.listApps[state.listApps.count - 1].enabled = true

        // TrustMe notices the grant.
        guard await pause(0.6) else { return }
        model.phase = .granted
        state.granted.insert(permission.id)
        state.activeID = nil

        // Like `dismissesOnGrant` + `activatesAppOnGrant`: the band leaves, TrustMe comes forward.
        guard await pause(1.4) else { return }
        model.isPresented = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            band.animator().alphaValue = 0
            band.animator().setFrameOrigin(CGPoint(x: band.frame.minX, y: band.frame.minY - 12))
        }, completionHandler: nil)
        trust.level = Demo.level(4)
        trust.orderFrontRegardless()
        _ = await move(to: CGPoint(x: trust.frame.midX + 60, y: trust.frame.minY + 120), duration: 1.0)
        _ = await pause(3.0)
    }

    private func tearDown() async {
        withAnimation(.easeOut(duration: 0.3)) { state.cursorVisible = false }
        for window in [trustWindow, settingsWindow, band, authWindow].compactMap({ $0 }) { fadeOut(window) }
        _ = await pause(1.0)
    }

    // MARK: - Windows

    private func makeTrustWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: PermissionsPane(state: state, app: app).background(WindowGlass()).preferredColorScheme(.dark))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        prepare(window, level: 2)
        // Size it now so it can be positioned before it's shown.
        window.setContentSize(hosting.view.fittingSize)
        trustWindow = window
        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: SettingsPane.size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: SettingsPane(state: state).preferredColorScheme(.dark))
        prepare(window, level: 3)
        settingsWindow = window
        return window
    }

    private func presentBand(beside settings: CGRect) -> (GuidePanel, GuideModel) {
        let model = GuideModel(permission: .accessibility, app: app)
        let hosting = FirstMouseHostingView(rootView: DragGuideView(model: model))
        hosting.layoutSubtreeIfNeeded()
        let panel = GuidePanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize))
        panel.contentView = hosting
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = Demo.level(5)
        panel.ignoresMouseEvents = true

        let (origin, edge) = GuidePlacement.place(panelSize: panel.frame.size, beside: settings, within: visible)
        model.edge = edge
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        model.isPresented = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        band = panel
        self.model = model
        return (panel, model)
    }

    private func presentAuth(over settings: CGRect) -> NSWindow {
        let hosting = NSHostingView(rootView: AuthPrompt(state: state))
        let size = hosting.fittingSize
        let window = DemoWindow(frame: CGRect(origin: .zero, size: size), level: Demo.level(6))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: settings.midX - size.width / 2, y: settings.midY - size.height / 2 + 20))
        authWindow = window
        fadeIn(window)
        return window
    }

    private func prepare(_ window: NSWindow, level: Int) {
        window.isReleasedWhenClosed = false
        window.level = Demo.level(level)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.animationBehavior = .none
        window.ignoresMouseEvents = true
    }

    /// Eased window move. Driven by hand: `animator()` frame changes don't
    /// reliably run for windows at these levels.
    private func slide(_ window: NSWindow, to target: CGPoint, duration: Double) {
        let start = window.frame.origin
        let began = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(began) / duration)
                let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                window.setFrameOrigin(CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased))
                if t >= 1 { timer.invalidate() }
            }
        }
    }

    private func fadeIn(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        }
    }

    private func clearWindows() {
        for window in [trustWindow, settingsWindow, band, authWindow].compactMap({ $0 }) { window.orderOut(nil) }
        trustWindow = nil
        settingsWindow = nil
        band = nil
        authWindow = nil
        model = nil
        Anchors.frames = [:]
        backdrop.makeKey()
    }

    // MARK: - Pointer

    private func overlayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
    }

    /// Glides the pointer to a screen point; false if the run was cancelled.
    private func move(to point: CGPoint, duration: Double) async -> Bool {
        withAnimation(.timingCurve(0.45, 0.05, 0.25, 1, duration: duration)) {
            state.cursor = overlayPoint(point)
        }
        return await pause(duration)
    }

    private func click(pressing id: String) async -> Bool {
        state.clicks.append(.init(point: state.cursor))
        state.pressedID = id
        let ok = await pause(0.15)
        state.pressedID = nil
        return ok
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

nonisolated(unsafe) var director: Director?

Demo.run {
    director = Director()
    director?.launch()
}
