import AppKit
import Observation
import SwiftUI
@testable import TrustMe

/// Everything the scripted demo changes over time. Nothing reads real TCC state.
@MainActor
@Observable
final class DemoState {
    enum CursorKind { case arrow, openHand, closedHand, dragCopy }

    struct ListApp: Identifiable {
        let name: String
        let icon: NSImage
        var enabled: Bool
        var id: String { name }
    }

    // TrustMe's window
    var granted: Set<String> = []
    var activeID: String?
    var pressedID: String?

    // System Settings
    var listApps: [ListApp] = []
    var dropTargeted = false

    // Authorization prompt
    var touchAccepted = false

    // Pointer, in overlay coordinates (top-left origin)
    var cursor = CGPoint.zero
    var cursorKind = CursorKind.arrow
    var cursorVisible = false
    var chipVisible = false
    var clicks: [Click] = []

    struct Click: Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    func reset() {
        granted = []
        activeID = nil
        pressedID = nil
        listApps = Self.existingApps()
        dropTargeted = false
        touchAccepted = false
        cursorKind = .arrow
        chipVisible = false
        clicks = []
    }

    /// A few apps already in the user's Accessibility list, taken from what's installed.
    private static func existingApps() -> [ListApp] {
        let candidates = ["Granola", "Raycast", "1Password", "Ghostty", "Arc", "Rectangle", "Alfred 5"]
        let installed = candidates.filter { FileManager.default.fileExists(atPath: "/Applications/\($0).app") }
        var apps = installed.prefix(3).enumerated().map { index, name in
            ListApp(name: name, icon: NSWorkspace.shared.icon(forFile: "/Applications/\(name).app"), enabled: index != 1)
        }
        if apps.isEmpty {
            let terminal = "/System/Applications/Utilities/Terminal.app"
            apps = [ListApp(name: "Terminal", icon: NSWorkspace.shared.icon(forFile: terminal), enabled: true)]
        }
        return apps
    }
}

/// Frames of named views, so the scripted pointer can find buttons and lists.
@MainActor
enum Anchors {
    static var frames: [String: CGRect] = [:]

    /// The anchor's frame in screen coordinates (bottom-left origin).
    static func screenRect(_ id: String, in window: NSWindow) -> CGRect? {
        guard let frame = frames[id] else { return nil }
        // Every demo window draws under its title bar, so content spans the frame.
        return CGRect(x: window.frame.minX + frame.minX, y: window.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
}

extension View {
    func anchor(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { Anchors.frames[id] = frame }
                    .onChange(of: frame) { _, new in Anchors.frames[id] = new }
            }
        }
    }
}
