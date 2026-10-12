import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import SwiftUI
import TrustMeProbe

/// The authorization state of a privacy permission.
public enum PermissionStatus: Sendable, Equatable {
    case granted
    /// Turned on in System Settings, but only takes effect after the app
    /// relaunches (Screen Recording, Input Monitoring).
    case needsRelaunch
    case notGranted
    /// macOS offers no reliable, prompt-free way to read this permission.
    case unknown
}

/// A macOS privacy permission.
///
/// Most are granted by dragging the app into a System Settings › Privacy &
/// Security list. Prompt-based ones (Camera, Microphone) are asked for with the
/// system prompt instead; once refused, only System Settings can turn them on.
///
/// Built-in permissions are exposed as static members. Create your own by
/// supplying a settings anchor and a status check, plus `canRequest` and
/// `request` for prompt-based permissions.
public struct Permission: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let systemImage: String
    public let tint: Color
    /// Deeplink that opens the matching System Settings pane.
    public let settingsURL: URL
    /// The `tccutil` service name, handy for resetting during development.
    public let tccService: String?
    /// Some permissions (Screen Recording, Input Monitoring) only take effect
    /// after the app relaunches.
    public let requiresRelaunch: Bool
    private let check: @Sendable () -> PermissionStatus
    private let canRequestCheck: (@Sendable () -> Bool)?
    private let requester: (@Sendable () async -> Void)?

    public init(
        id: String,
        title: String,
        summary: String,
        systemImage: String,
        tint: Color,
        settingsAnchor: String,
        tccService: String? = nil,
        requiresRelaunch: Bool = false,
        check: @escaping @Sendable () -> PermissionStatus,
        canRequest: (@Sendable () -> Bool)? = nil,
        request: (@Sendable () async -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.tint = tint
        self.settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!
        self.tccService = tccService
        self.requiresRelaunch = requiresRelaunch
        self.check = check
        self.canRequestCheck = canRequest
        self.requester = request
    }

    /// Reads the current status without triggering any system prompt.
    public func currentStatus() -> PermissionStatus { check() }

    /// Granted through a system prompt rather than by dragging into a list.
    public var isPromptBased: Bool { requester != nil }

    /// Whether the system prompt can still be shown. False once the user has
    /// answered it; from then on only System Settings can change the answer.
    public func canRequest() -> Bool { canRequestCheck?() ?? false }

    /// Shows the system prompt. Does nothing for drag-based permissions.
    public func request() async { await requester?() }

    public static func == (lhs: Permission, rhs: Permission) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension Permission {
    static let accessibility = Permission(
        id: "accessibility",
        title: "Accessibility",
        summary: "Control your Mac: click, type and navigate other apps.",
        systemImage: "accessibility",
        tint: Color(red: 0.24, green: 0.52, blue: 1.0),
        settingsAnchor: "Privacy_Accessibility",
        tccService: "Accessibility",
        check: { AXIsProcessTrusted() ? .granted : TCC.status("Accessibility") ?? .notGranted }
    )

    static let screenRecording = Permission(
        id: "screen-recording",
        title: "Screen Recording",
        summary: "See the contents of windows and the screen.",
        systemImage: "rectangle.dashed.badge.record",
        tint: Color(red: 0.95, green: 0.27, blue: 0.42),
        settingsAnchor: "Privacy_ScreenCapture",
        tccService: "ScreenCapture",
        requiresRelaunch: true,
        check: { liveOrPendingRelaunch(CGPreflightScreenCaptureAccess(), service: "ScreenCapture") }
    )

    static let inputMonitoring = Permission(
        id: "input-monitoring",
        title: "Input Monitoring",
        summary: "Listen to keyboard shortcuts while in the background.",
        systemImage: "keyboard.badge.eye",
        tint: Color(red: 0.62, green: 0.38, blue: 1.0),
        settingsAnchor: "Privacy_ListenEvent",
        tccService: "ListenEvent",
        requiresRelaunch: true,
        check: { liveOrPendingRelaunch(CGPreflightListenEventAccess(), service: "ListenEvent") }
    )

    static let fullDiskAccess = Permission(
        id: "full-disk-access",
        title: "Full Disk Access",
        summary: "Read files in protected locations like Mail and Safari.",
        systemImage: "internaldrive",
        tint: Color(red: 0.16, green: 0.72, blue: 0.62),
        settingsAnchor: "Privacy_AllFiles",
        tccService: "SystemPolicyAllFiles",
        check: {
            if let status = TCC.currentStatus("SystemPolicyAllFiles") { return status }
            // The user TCC database is only readable with Full Disk Access.
            let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
            guard FileManager.default.fileExists(atPath: path) else { return .unknown }
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return .granted }
            return .notGranted
        }
    )

    static let appManagement = Permission(
        id: "app-management",
        title: "App Management",
        summary: "Update or delete other apps on this Mac.",
        systemImage: "square.grid.3x3.square",
        tint: Color(red: 1.0, green: 0.58, blue: 0.18),
        settingsAnchor: "Privacy_AppBundles",
        tccService: "SystemPolicyAppBundles",
        check: { TCC.currentStatus("SystemPolicyAppBundles") ?? .unknown }
    )

    static let developerTools = Permission(
        id: "developer-tools",
        title: "Developer Tools",
        summary: "Run software that doesn't meet the system's security policy.",
        systemImage: "hammer",
        tint: Color(red: 0.45, green: 0.5, blue: 0.6),
        settingsAnchor: "Privacy_DevTools",
        tccService: "DeveloperTool",
        check: { TCC.currentStatus("DeveloperTool") ?? .unknown }
    )

    static let camera = Permission(
        id: "camera",
        title: "Camera",
        summary: "Show your camera in recordings and calls.",
        systemImage: "camera",
        tint: Color(red: 0.2, green: 0.78, blue: 0.35),
        settingsAnchor: "Privacy_Camera",
        tccService: "Camera",
        check: { captureStatus(for: .video) },
        canRequest: { AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined },
        request: { _ = await AVCaptureDevice.requestAccess(for: .video) }
    )

    static let microphone = Permission(
        id: "microphone",
        title: "Microphone",
        summary: "Record your voice in recordings and calls.",
        systemImage: "mic",
        tint: Color(red: 1.0, green: 0.45, blue: 0.25),
        settingsAnchor: "Privacy_Microphone",
        tccService: "Microphone",
        check: { captureStatus(for: .audio) },
        canRequest: { AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined },
        request: { _ = await AVCaptureDevice.requestAccess(for: .audio) }
    )

    /// Permissions granted by dragging the app into a System Settings list.
    static let allDraggable: [Permission] = [
        .accessibility, .screenRecording, .inputMonitoring, .fullDiskAccess, .appManagement, .developerTools,
    ]

    /// Permissions granted through a system prompt.
    static let allPromptBased: [Permission] = [.camera, .microphone]

    static let all: [Permission] = allDraggable + allPromptBased
}

private func captureStatus(for media: AVMediaType) -> PermissionStatus {
    AVCaptureDevice.authorizationStatus(for: media) == .authorized ? .granted : .notGranted
}

/// Public APIs for Screen Recording and Input Monitoring cache their answer
/// for the life of the process; TCC knows sooner, so a grant that hasn't
/// taken effect yet reads as `needsRelaunch`.
private func liveOrPendingRelaunch(_ live: Bool, service: String) -> PermissionStatus {
    PermissionStatus.resolve(live: live, tcc: live ? nil : TCC.status(service))
}

extension PermissionStatus {
    /// Combines a public API's cached answer with TCC's current one.
    static func resolve(live: Bool, tcc: PermissionStatus?) -> PermissionStatus {
        if live { return .granted }
        return tcc == .granted ? .needsRelaunch : .notGranted
    }
}

/// Reads this app's authorization straight from TCC, without prompting.
///
/// `TCCAccessPreflight` is private API: it's the only way to read App
/// Management and Developer Tools, and it reflects grants immediately. When
/// it's unavailable every check falls back to public APIs or `.unknown`.
enum TCC {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32

    private static let preflight: Preflight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(handle, "TCCAccessPreflight")
        else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)
    }()

    /// Like ``status(_:)``, but double-checks a denial from a fresh process,
    /// since in-process answers can stay stuck on "denied" after a grant.
    static func currentStatus(_ service: String) -> PermissionStatus? {
        let local = status(service)
        guard local == .notGranted else { return local }
        return FreshProbe.status(service) ?? local
    }

    static func status(_ service: String) -> PermissionStatus? {
        guard let preflight else { return nil }
        switch preflight("kTCCService\(service)" as CFString, nil) {
        case 0: return .granted
        case 1: return .notGranted
        default: return nil
        }
    }
}

/// Asks TCC from a new process: the app's own executable, relaunched with
/// `TRUSTME_TCC_PROBE` set, which the TrustMeProbe constructor answers on
/// stdout before the app starts. Results are reused for a couple of seconds.
enum FreshProbe {
    nonisolated(unsafe) private static var cache: [String: (status: PermissionStatus?, at: Date)] = [:]
    private static let lock = NSLock()

    static func status(_ service: String) -> PermissionStatus? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[service], Date().timeIntervalSince(cached.at) < 2 { return cached.status }

        trustme_probe_anchor()
        // Only re-execute a real app: a test runner or CLI tool would just run
        // again, and a probe must never start probes of its own.
        guard Bundle.main.bundleURL.pathExtension == "app",
              ProcessInfo.processInfo.environment["TRUSTME_TCC_PROBE"] == nil
        else { return nil }
        let result = Bundle.main.executableURL.flatMap { run(service: "kTCCService\(service)", executable: $0) }
        cache[service] = (result, Date())
        return result
    }

    /// Runs `executable` as a probe. Returns nil unless it answers with the
    /// probe token in time — e.g. when TrustMe isn't linked into it, so the
    /// constructor never ran and the program just started normally.
    static func run(service: String, executable: URL, timeout: TimeInterval = 2) -> PermissionStatus? {
        let process = Process()
        process.executableURL = executable
        process.environment = ["TRUSTME_TCC_PROBE": service]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        guard (try? process.run()) != nil else { return nil }

        // Read concurrently so a chatty program can't block on a full pipe.
        // Only touched before `readDone` is signalled and after it's awaited.
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = output.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            kill(process.processIdentifier, SIGKILL)
            _ = readDone.wait(timeout: .now() + 1)
            return nil
        }
        guard readDone.wait(timeout: .now() + 1) == .success,
              let text = String(data: box.data, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("TRUSTME_PROBE:") })
        else { return nil }

        switch line.dropFirst("TRUSTME_PROBE:".count) {
        case "0": return .granted
        case "1": return .notGranted
        default: return nil
        }
    }
}
