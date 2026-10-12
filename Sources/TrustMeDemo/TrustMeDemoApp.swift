import AppKit
import SwiftUI
import TrustMe

@main
struct TrustMeDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The onboarding window is an AppKit window owned by TrustMe.
        Settings { EmptyView() }
            .commands {
                CommandMenu("Demo") {
                    Button("Show Permissions") { appDelegate.showOnboarding() }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                    Divider()
                    Button("Reset All Permissions") { appDelegate.resetPermissions() }
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = Permission.all

    func applicationDidFinishLaunching(_ notification: Notification) {
        Relauncher.install()
        let args = ProcessInfo.processInfo.arguments

        // `--print-status` prints what TrustMe detects and exits.
        if args.contains("--print-status") {
            for permission in permissions {
                print(permission.id, permission.currentStatus())
            }
            exit(0)
        }

        NSApp.setActivationPolicy(.regular)
        showOnboarding()

        // `--auto-request <permission-id>` starts a flow on launch (handy for demos and
        // screenshots); `--auto-request-delay <seconds>` postpones it.
        if let index = args.firstIndex(of: "--auto-request"), index + 1 < args.count,
           let permission = permissions.first(where: { $0.id == args[index + 1] }) {
            let delay = args.firstIndex(of: "--auto-request-delay")
                .flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                PermissionFlow.shared.authorize(permission)
            }
        }
    }

    func showOnboarding() {
        PermissionsWindow.show(
            permissions,
            optional: [.appManagement, .developerTools],
            message: Relauncher.wasRelaunchedForPermissions ? "Welcome back. Pick up where you left off." : nil,
            continueTitle: "Done"
        ) { allGranted in
            print("Onboarding finished. All required granted: \(allGranted)")
        }
    }

    func resetPermissions() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for service in permissions.compactMap(\.tccService) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            try? process.run()
            process.waitUntilExit()
        }
        PermissionCenter.shared.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showOnboarding() }
        return true
    }
}
