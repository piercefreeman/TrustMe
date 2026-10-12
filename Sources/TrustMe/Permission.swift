import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

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

/// A macOS privacy permission that can be granted by dragging an app into a
/// System Settings › Privacy & Security list.
///
/// Built-in permissions are exposed as static members. Create your own by
/// supplying a settings anchor and a status check.
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

    public init(
        id: String,
        title: String,
        summary: String,
        systemImage: String,
        tint: Color,
        settingsAnchor: String,
        tccService: String? = nil,
        requiresRelaunch: Bool = false,
        check: @escaping @Sendable () -> PermissionStatus
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
    }

    /// Reads the current status without triggering any system prompt.
    public func currentStatus() -> PermissionStatus { check() }

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
            if let status = TCC.status("SystemPolicyAllFiles") { return status }
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
        check: { TCC.status("SystemPolicyAppBundles") ?? .unknown }
    )

    static let developerTools = Permission(
        id: "developer-tools",
        title: "Developer Tools",
        summary: "Run software that doesn't meet the system's security policy.",
        systemImage: "hammer",
        tint: Color(red: 0.45, green: 0.5, blue: 0.6),
        settingsAnchor: "Privacy_DevTools",
        tccService: "DeveloperTool",
        check: { TCC.status("DeveloperTool") ?? .unknown }
    )

    static let allDraggable: [Permission] = [
        .accessibility, .screenRecording, .inputMonitoring, .fullDiskAccess, .appManagement, .developerTools,
    ]
}

/// Public APIs for Screen Recording and Input Monitoring cache their answer
/// for the life of the process; TCC knows sooner, so a grant that hasn't
/// taken effect yet reads as `needsRelaunch`.
private func liveOrPendingRelaunch(_ live: Bool, service: String) -> PermissionStatus {
    if live { return .granted }
    return TCC.status(service) == .granted ? .needsRelaunch : .notGranted
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

    static func status(_ service: String) -> PermissionStatus? {
        guard let preflight else { return nil }
        switch preflight("kTCCService\(service)" as CFString, nil) {
        case 0: return .granted
        case 1: return .notGranted
        default: return nil
        }
    }
}
