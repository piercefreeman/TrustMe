import AppKit

/// Brings the app back after macOS quits it to apply a permission.
///
/// Granting Screen Recording or Input Monitoring makes System Settings offer
/// "Quit & Reopen"; other paths just quit the app. TrustMe watches for a quit
/// sent by System Settings and relaunches the app once it has exited, setting
/// ``wasRelaunchedForPermissions`` so onboarding can pick up where it left off.
@MainActor
public enum Relauncher {
    /// Relaunch automatically when System Settings quits the app. Default `true`.
    public static var relaunchesAfterSystemQuit = true

    /// True when this launch is the result of a TrustMe relaunch. Read it at
    /// startup to resume onboarding; it resets on the next launch.
    public private(set) static var wasRelaunchedForPermissions = false

    private static let resumeKey = "TrustMe.relaunchedForPermissions"
    private static var isInstalled = false

    /// Hooks app termination. Called automatically by ``PermissionFlow`` and
    /// ``PermissionsWindow``; call it yourself at launch to read the resume flag
    /// before showing any UI.
    public static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        wasRelaunchedForPermissions = consumeResumeFlag(in: .standard)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                guard relaunchesAfterSystemQuit, quitWasSentBySystemSettings() else { return }
                scheduleRelaunch()
            }
        }
    }

    /// Reads and clears the flag a TrustMe relaunch leaves behind.
    static func consumeResumeFlag(in defaults: UserDefaults) -> Bool {
        let flag = defaults.bool(forKey: resumeKey)
        defaults.removeObject(forKey: resumeKey)
        return flag
    }

    static func setResumeFlag(in defaults: UserDefaults) {
        defaults.set(true, forKey: resumeKey)
    }

    /// Quits and reopens the app, e.g. after granting a permission that only
    /// takes effect on relaunch.
    public static func relaunch() {
        scheduleRelaunch()
        NSApp.terminate(nil)
    }

    /// Starts a detached helper that waits for this process to exit, then
    /// reopens the bundle. It outlives us because it isn't our child job.
    private static func scheduleRelaunch() {
        setResumeFlag(in: .standard)
        UserDefaults.standard.synchronize()

        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; sleep 0.3; /usr/bin/open \"$0\"",
            Bundle.main.bundleURL.path,
        ]
        try? helper.run()
    }

    private static func quitWasSentBySystemSettings() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
              let sender = event.attributeDescriptor(forKeyword: keySenderPIDAttr)
        else { return false }
        let pid = pid_t(sender.int32Value)
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == SystemSettingsWindow.bundleIdentifier
    }
}
