import AppKit
import CoreGraphics

/// Locates the frontmost System Settings window via the Window Server.
/// Window bounds and owner info don't require Screen Recording access.
@MainActor
enum SystemSettingsWindow {
    static let bundleIdentifier = "com.apple.systempreferences"

    /// The main System Settings window frame in Cocoa screen coordinates
    /// (origin bottom-left of the primary display), or nil if none is visible.
    static func currentFrame() -> CGRect? { locate(above: nil)?.frame }

    /// System Settings' frontmost on-screen window, and whether window
    /// `number` is stacked above it.
    static func locate(above number: Int?) -> (frame: CGRect, isBehind: Bool)? {
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .map(\.processIdentifier)
        )
        return locate(owners: pids, above: number)
    }

    /// The frontmost on-screen window owned by `owners`, read live from the
    /// Window Server. Window bounds and stacking order don't need Screen Recording.
    static func locate(owners pids: Set<pid_t>, above number: Int?) -> (frame: CGRect, isBehind: Bool)? {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        return frontmost(in: list, pids: pids, above: number, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// The first sizeable normal window owned by `pids` in a front-to-back
    /// window list, and whether window `number` comes before it.
    nonisolated static func frontmost(in list: [[String: Any]], pids: Set<pid_t>, above number: Int?,
                                      primaryHeight: CGFloat) -> (frame: CGRect, isBehind: Bool)? {
        var seenAbove = false
        for info in list {
            if let number, (info[kCGWindowNumber as String] as? Int) == number { seenAbove = true }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 300, bounds.height > 200
            else { continue }
            return (cocoaRect(fromWindowServer: bounds, primaryHeight: primaryHeight), seenAbove)
        }
        return nil
    }

    /// Window Server rects are top-left based on the primary display.
    nonisolated static func cocoaRect(fromWindowServer rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Where the guide panel sits relative to the System Settings window. The
/// drag hint points the opposite way, toward the permission list.
public enum GuideEdge: Sendable {
    case below, right, left, inside

    /// Where the list is, relative to the panel.
    var direction: String {
        switch self {
        case .below, .inside: "above"
        case .right: "to the left"
        case .left: "to the right"
        }
    }
}

enum GuidePlacement {
    static let gap: CGFloat = 14

    /// Chooses a spot next to the settings window, preferring the space under
    /// its content pane (where the app list lives).
    @MainActor
    static func place(panelSize size: CGSize, beside settings: CGRect) -> (CGPoint, GuideEdge) {
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? settings.insetBy(dx: -2000, dy: -2000)
        return place(panelSize: size, beside: settings, within: visible)
    }

    /// - Parameter visible: The usable area of the screen holding the window.
    static func place(panelSize size: CGSize, beside settings: CGRect, within visible: CGRect) -> (CGPoint, GuideEdge) {

        // The privacy list occupies the pane to the right of the sidebar.
        let sidebar = min(260, settings.width * 0.32)
        let contentMidX = settings.minX + sidebar + (settings.width - sidebar) / 2

        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, visible.minX + 8), visible.maxX - size.width - 8) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, visible.minY + 8), visible.maxY - size.height - 8) }

        let belowY = settings.minY - gap - size.height
        if belowY >= visible.minY {
            return (CGPoint(x: clampX(contentMidX - size.width / 2), y: belowY), .below)
        }
        let rightX = settings.maxX + gap
        if rightX + size.width <= visible.maxX {
            return (CGPoint(x: rightX, y: clampY(settings.midY - size.height / 2)), .right)
        }
        let leftX = settings.minX - gap - size.width
        if leftX >= visible.minX {
            return (CGPoint(x: leftX, y: clampY(settings.midY - size.height / 2)), .left)
        }
        return (CGPoint(x: clampX(contentMidX - size.width / 2), y: clampY(settings.minY + 28)), .inside)
    }
}
