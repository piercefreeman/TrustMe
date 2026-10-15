import AppKit
import Testing
@testable import TrustMe

private final class BundleAnchor {}

/// Waits, suspended, until `condition` holds, for what the window server,
/// another process or AppKit's main-queue callbacks do on their own time.
/// Suspending rather than spinning the run loop: the test itself runs on the
/// main queue, so main-queue work (animation completions) only runs once it yields.
@MainActor
func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// Waits until `condition` has held across several polls in a row, so a
/// window list caught mid-update can't pass by luck.
@MainActor
func settles(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    var streak = 0
    return await eventually(timeout: timeout) {
        streak = condition() ? streak + 1 : 0
        return streak >= 5
    }
}

/// Waits for the window server to list `window`; for a moment after it's
/// ordered front it isn't there at all.
@MainActor
func listed(_ window: NSWindow) async -> Bool {
    await eventually {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.contains { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
    }
}

/// The TrustMeWindowHost executable: another process with one real window.
@MainActor
final class WindowHost {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    /// The window's frame as the host last reported it, in Cocoa coordinates.
    private(set) var frame = CGRect.zero

    var pid: pid_t { process.processIdentifier }

    init(frame: CGRect) async throws {
        process.executableURL = Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("TrustMeWindowHost")
        process.arguments = [frame.minX, frame.minY, frame.width, frame.height].map { "\($0)" }
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        read("ready")
        // Listed by the window server, whatever its size.
        let pid = pid
        _ = await eventually {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            return list.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
        }
    }

    /// Sends a command and waits for the host to have carried it out.
    func send(_ command: String) {
        input.fileHandleForWriting.write(Data((command + "\n").utf8))
        read("done")
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
    }

    private func read(_ word: String) {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                let parts = line.split(separator: " ")
                guard parts.first.map(String.init) == word else { continue }
                let n = parts.dropFirst().compactMap { Double($0) }
                frame = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
                return
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
        }
    }
}

@Suite("Window list, against another process's real window", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct WindowListTests {
    let screen = NSScreen.screens.first!.visibleFrame

    var settingsFrame: CGRect {
        CGRect(x: (screen.midX - 357).rounded(), y: (screen.midY - 300).rounded(), width: 715, height: 600)
    }

    func ours(at frame: CGRect) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        return window
    }

    @Test("Finds the window by its owner, in Cocoa coordinates")
    func finds() async throws {
        let host = try await WindowHost(frame: settingsFrame)
        defer { host.stop() }
        var found: CGRect?
        #expect(await eventually {
            found = SystemSettingsWindow.locate(owners: [host.pid], above: nil)?.frame
            return found != nil
        })
        #expect(found == host.frame)
    }

    @Test("Follows it as it moves, and loses it once it's hidden")
    func movesAndHides() async throws {
        let host = try await WindowHost(frame: settingsFrame)
        defer { host.stop() }
        let moved = settingsFrame.offsetBy(dx: -120, dy: -40)
        host.send("move \(moved.minX) \(moved.minY) \(moved.width) \(moved.height)")
        #expect(await eventually { SystemSettingsWindow.locate(owners: [host.pid], above: nil)?.frame == moved })
        host.send("hide")
        #expect(await eventually { SystemSettingsWindow.locate(owners: [host.pid], above: nil) == nil })
    }

    @Test("Reads which of two processes' windows is in front")
    func stacking() async throws {
        let host = try await WindowHost(frame: settingsFrame)
        defer { host.stop() }
        let window = ours(at: settingsFrame.insetBy(dx: 100, dy: 100))
        defer { window.orderOut(nil) }

        window.orderFrontRegardless()
        #expect(await listed(window))
        #expect(await settles { SystemSettingsWindow.locate(owners: [host.pid], above: window.windowNumber)?.isBehind == true })
        host.send("front")
        #expect(await settles { SystemSettingsWindow.locate(owners: [host.pid], above: window.windowNumber)?.isBehind == false })
    }

    @Test("Ignores windows too small to be Settings' main window")
    func small() async throws {
        let host = try await WindowHost(frame: CGRect(x: screen.minX + 40, y: screen.minY + 40, width: 280, height: 180))
        defer { host.stop() }
        #expect(SystemSettingsWindow.locate(owners: [host.pid], above: nil) == nil)
    }

    @Test("A dodge steps a real window off another process's window, and back once it's gone")
    func dodges() async throws {
        // Over the right half of the dodging window, leaving room to its left on any screen.
        let host = try await WindowHost(frame: DodgeRig.overlapping(DodgeRig.home))
        defer { host.stop() }
        let rig = DodgeRig { SystemSettingsWindow.locate(owners: [host.pid], above: $0.windowNumber) }
        defer { rig.close() }
        rig.window.orderFrontRegardless()
        #expect(await listed(rig.window))
        #expect(await settles { SystemSettingsWindow.locate(owners: [host.pid], above: rig.window.windowNumber)?.isBehind == true })

        rig.openPane()
        rig.settle()
        #expect(rig.isAside)
        #expect(!rig.window.frame.intersects(host.frame))

        host.send("hide")
        #expect(await eventually { SystemSettingsWindow.locate(owners: [host.pid], above: nil) == nil })
        rig.tick()
        #expect(rig.window.frame == rig.home)
    }
}
