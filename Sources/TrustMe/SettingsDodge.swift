import AppKit

/// Slides a window out from over System Settings when the app has sent the
/// person there, and back once they're done. A window that floats (or simply
/// sits) where Settings opens would otherwise hide the very list they need.
///
/// ```swift
/// let dodge = SettingsDodge(window: onboardingWindow)
/// dodge.start()
/// // …
/// dodge.stop()
/// ```
///
/// A trip is either a ``PermissionFlow`` grant (the window comes back once
/// it's granted) or a pane opened with ``open(_:)`` (back once Settings
/// closes). Settings visited any other time is left alone, and a click on the
/// window while it's aside leaves it where it is for the rest of that trip.
/// ``PermissionsWindow`` runs one of these for itself.
@MainActor
public final class SettingsDodge {
    private enum Trip: Equatable {
        case grant(Permission)
        case pane(Date)
    }

    /// When a Settings pane was last opened outside a grant.
    private static var paneOpened: Date?

    /// Opens a System Settings pane, with every dodge ready to step aside for it.
    public static func open(_ url: URL) {
        paneOpened = Date()
        NSWorkspace.shared.open(url)
    }

    private weak var window: NSWindow?
    private let flow: PermissionFlow
    private var timer: Timer?
    private var clicks: Any?
    private var trip: Trip?
    /// The last pane trip seen, so each is taken up once.
    private var lastPane: Date?
    /// Where the window was before it moved aside; nil while it isn't aside.
    private var home: NSRect?
    /// Where it was moved to, to tell whether the person has moved it since.
    private var aside: NSRect?
    /// The person clicked the window while it was aside: its place is theirs.
    private var released = false
    private var lastSettings: CGRect?
    private var settingsStableSince: Date?

    static let tick: TimeInterval = 0.2
    /// Settings must hold still this long first: it launches, resizes and
    /// navigates, and the window shouldn't chase it.
    static let settle: TimeInterval = 0.3
    /// How long a pane trip waits for Settings to show up under the window.
    static let paneWait: TimeInterval = 10

    /// - Parameter flow: The flow whose grants count as trips to Settings.
    public init(window: NSWindow, flow: PermissionFlow = .shared) {
        self.window = window
        self.flow = flow
        lastPane = Self.paneOpened
    }

    /// Starts watching. Safe to call more than once.
    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // A click, not activation: the flow brings the app forward itself once a grant is done.
        clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window != nil, event.window === self.window { self.release() }
            }
            return event
        }
    }

    /// Stops watching, leaving the window where it is.
    public func stop() {
        timer?.invalidate()
        timer = nil
        clicks.map(NSEvent.removeMonitor)
        clicks = nil
        end()
    }

    /// Only a click while aside counts: one before (Allow again, Open
    /// settings) mustn't stop the window from getting out of the way.
    private func release() {
        guard trip != nil, home != nil, !released else { return }
        released = true
        home = nil
        aside = nil
    }

    private func begin(_ trip: Trip) {
        end()
        self.trip = trip
    }

    private func end() {
        trip = nil
        released = false
        home = nil
        aside = nil
        lastSettings = nil
        settingsStableSince = nil
    }

    /// Back where it was, unless the person has moved it since.
    private func comeBack() {
        guard let window, let home, let aside, window.frame == aside else { return }
        window.setFrame(home, display: true, animate: true)
    }

    private func check() {
        guard let window, window.isVisible else { return }
        let active = flow.activePermission
        if let active {
            if trip != .grant(active) { begin(.grant(active)) }
        } else if let opened = Self.paneOpened, opened != lastPane {
            lastPane = opened
            begin(.pane(opened))
        }
        let settings = Self.settingsWindow(relativeTo: window)

        switch trip {
        case nil:
            return
        case .grant(let permission):
            let status = PermissionCenter.shared.status(of: permission)
            if status == .granted || status == .needsRelaunch {
                // Dragged in: the only time the window comes back.
                comeBack()
                if active == nil { end() } else { home = nil; aside = nil; released = true }
                return
            }
            // The guide closed without a grant: the window stays where it is.
            guard active != nil else { return end() }
        case .pane(let opened):
            if home != nil, settings == nil {
                comeBack()
                return end()
            }
            // Never under the window (or never came): nothing to get out of the way of.
            if home == nil, !released, Date().timeIntervalSince(opened) > Self.paneWait { return end() }
        }

        guard !released else { return }
        guard let settings else {
            lastSettings = nil
            settingsStableSince = nil
            return
        }
        if settings.frame != lastSettings {
            lastSettings = settings.frame
            settingsStableSince = Date()
            return
        }
        guard let since = settingsStableSince, Date().timeIntervalSince(since) >= Self.settle else { return }
        if let aside, window.frame != aside {
            // Moved by hand while aside: that's where the person wants it.
            return release()
        }
        // Settings is under this window, whether or not it's the active app.
        guard home != nil || (settings.isBehind && window.frame.intersects(settings.frame)) else { return }
        let visible = (NSScreen.screens.first { $0.frame.intersects(settings.frame) } ?? window.screen ?? NSScreen.main)?
            .visibleFrame ?? settings.frame
        let target = Self.place(window.frame.size, besides: settings.frame, within: visible, from: home ?? window.frame)
        guard target != aside else { return }
        if home == nil { home = window.frame }
        window.setFrame(target, display: true, animate: true)
        // What the window server made of it, so rounding doesn't read as a move by hand.
        aside = window.frame
    }

    /// Where a window of `size` goes so it no longer covers `settings`:
    /// beside it on whichever side has more room (ties go to the side it was
    /// already on), at its own height. When that side is short of room it
    /// hangs off the screen's edge, keeping `minimumShown` points on screen.
    nonisolated static func place(_ size: CGSize, besides settings: CGRect, within visible: CGRect,
                                  from origin: CGRect, gap: CGFloat = 16, minimumShown: CGFloat = 240) -> CGRect {
        let y = min(max(origin.minY, visible.minY), visible.maxY - size.height)
        let leftRoom = settings.minX - gap - visible.minX
        let rightRoom = visible.maxX - (settings.maxX + gap)
        let goLeft = leftRoom == rightRoom ? origin.midX < settings.midX : leftRoom > rightRoom
        // Flush against the settings, the shortest move off them; or, short
        // of room, as far off the screen's edge as still leaves it clickable.
        let x = goLeft ? visible.minX + max(leftRoom, minimumShown) - size.width
                       : visible.maxX - max(rightRoom, minimumShown)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// System Settings' frontmost on-screen window, in Cocoa coordinates, and
    /// whether `window` is stacked above it. Window bounds and stacking order
    /// don't need Screen Recording.
    static func settingsWindow(relativeTo window: NSWindow) -> (frame: CGRect, isBehind: Bool)? {
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: SystemSettingsWindow.bundleIdentifier)
                .map(\.processIdentifier)
        )
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        return frontmostSettings(in: list, pids: pids, above: window.windowNumber,
                                 primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// The first sizeable normal window owned by `pids` in a front-to-back
    /// window list, and whether window `number` comes before it.
    nonisolated static func frontmostSettings(in list: [[String: Any]], pids: Set<pid_t>, above number: Int,
                                              primaryHeight: CGFloat) -> (frame: CGRect, isBehind: Bool)? {
        var seenAbove = false
        for info in list {
            if (info[kCGWindowNumber as String] as? Int) == number { seenAbove = true }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 300, bounds.height > 200 else { continue }
            return (CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height), seenAbove)
        }
        return nil
    }
}
