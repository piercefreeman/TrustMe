import AppKit
import CoreGraphics

/// The current desktop picture, without icons or windows.
///
/// Captures the Dock's wallpaper window for the screen (needs Screen
/// Recording for the terminal) and saves it to `Assets/wallpaper.png`, which
/// is the fallback when capture isn't possible. `--wallpaper <path>` overrides.
@MainActor
public enum Wallpaper {
    static let saved = Demo.packageRoot.appendingPathComponent("Assets/wallpaper.png")

    public static func load(for screen: NSScreen) -> NSImage? {
        let image: NSImage? = {
            if let path = Demo.arg("--wallpaper") { return NSImage(contentsOfFile: path) }
            if !Demo.flag("--saved-wallpaper"), let captured = capture(screen) { return captured }
            if let image = NSImage(contentsOf: saved) { return image }
            return NSWorkspace.shared.desktopImageURL(for: screen).flatMap(NSImage.init(contentsOf:))
        }()
        image?.size = screen.frame.size
        return image
    }

    private static func capture(_ screen: NSScreen) -> NSImage? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let bounds = CGDisplayBounds(displayID)

        // The Dock draws each display's wallpaper in its own desktop-level window.
        let window = list.first { info in
            guard (info[kCGWindowOwnerName as String] as? String) == "Dock",
                  (info[kCGWindowLayer as String] as? Int ?? 0) < 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict)
            else { return false }
            return frame == bounds
        }
        guard let id = window?[kCGWindowNumber as String] as? Int else { return nil }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("trustme-wallpaper-\(id).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(id), output.path]
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let image = NSImage(contentsOf: output) else { return nil }

        try? FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: saved)
        try? FileManager.default.copyItem(at: output, to: saved)
        return image
    }
}
