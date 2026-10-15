import AppKit
import SwiftUI

/// Shared plumbing: arguments, the demo's screen, window levels and keys.
public enum Demo {
    public static let args = ProcessInfo.processInfo.arguments

    public static func arg(_ name: String) -> String? {
        args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    public static func flag(_ name: String) -> Bool { args.contains(name) }

    /// The DemoVideos package directory.
    public static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @MainActor public static var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    /// Height of the real menu bar (taller on notched displays).
    @MainActor public static var menuBarHeight: CGFloat {
        let inset = screen.safeAreaInsets.top
        return inset > 0 ? inset : max(24, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// Everything sits above the real desktop, Dock and menu bar.
    public static func level(_ offset: Int) -> NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + offset)
    }

    // MARK: - The app being demoed

    public static let appURL = URL(fileURLWithPath: arg("--app") ?? packageRoot.appendingPathComponent("../build/TrustMe.app").standardized.path)
    public static let appName = arg("--name") ?? appURL.deletingPathExtension().lastPathComponent
    @MainActor public static var appIcon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }

    // MARK: - Keys

    @MainActor private static var monitor: Any?

    /// Esc (or ⌘Q) quits; R replays.
    @MainActor public static func installKeys(replay: @escaping () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.keyCode == 53 || (key == "q" && event.modifierFlags.contains(.command)) {
                NSApp.terminate(nil)
                return nil
            }
            if key == "r" { replay(); return nil }
            return event
        }
    }

    /// Starts an accessory app (no Dock icon) and hands control to `launch`.
    public static func run(_ launch: @escaping @MainActor () -> Void) -> Never {
        MainActor.assumeIsolated { start(launch) }
        exit(0)
    }

    @MainActor private static func start(_ launch: @escaping @MainActor () -> Void) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = LaunchDelegate(launch: launch)
        app.delegate = delegate
        app.run()
    }
}

private final class LaunchDelegate: NSObject, NSApplicationDelegate {
    let launch: @MainActor () -> Void
    init(launch: @escaping @MainActor () -> Void) { self.launch = launch }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { launch() }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A borderless window that can still take key events (for Esc).
public final class DemoWindow: NSWindow {
    public convenience init(frame: CGRect, level: NSWindow.Level) {
        self.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = level
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}
