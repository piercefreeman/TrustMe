import Foundation
import Testing
@testable import TrustMe

/// A thread-safe switch for driving a custom permission's status.
final class StatusSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PermissionStatus
    init(_ value: PermissionStatus) { self.value = value }
    var status: PermissionStatus {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@Suite("Permissions")
struct PermissionTests {
    @Test("Built-in permissions are distinct and point at Privacy panes")
    func builtIns() {
        let all = Permission.allDraggable
        #expect(Set(all.map(\.id)).count == all.count)
        for permission in all {
            #expect(permission.settingsURL.scheme == "x-apple.systempreferences")
            #expect(permission.settingsURL.absoluteString.contains("?Privacy_"))
            #expect(permission.tccService != nil)
            #expect(!permission.title.isEmpty && !permission.summary.isEmpty)
        }
    }

    @Test("Only Screen Recording and Input Monitoring need a relaunch")
    func relaunchSet() {
        let relaunching = Permission.allDraggable.filter(\.requiresRelaunch).map(\.id)
        #expect(Set(relaunching) == ["screen-recording", "input-monitoring"])
    }

    @Test("Identity is the id alone")
    func identity() {
        let a = Permission(id: "x", title: "A", summary: "", systemImage: "star", tint: .red, settingsAnchor: "Privacy_A") { .granted }
        let b = Permission(id: "x", title: "B", summary: "", systemImage: "moon", tint: .blue, settingsAnchor: "Privacy_B") { .notGranted }
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test("Custom permissions build their deeplink and run their check")
    func custom() {
        let state = StatusSwitch(.notGranted)
        let permission = Permission(id: "custom", title: "Custom", summary: "", systemImage: "star", tint: .red,
                                    settingsAnchor: "Privacy_Custom") { state.status }
        #expect(permission.settingsURL.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Custom")
        #expect(permission.currentStatus() == .notGranted)
        state.status = .granted
        #expect(permission.currentStatus() == .granted)
    }

    @Test("A grant TCC knows about but the live API doesn't yet needs a relaunch", arguments: [
        (true, PermissionStatus?.none, PermissionStatus.granted),
        (true, .notGranted, .granted),
        (false, .granted, .needsRelaunch),
        (false, .notGranted, .notGranted),
        (false, .unknown, .notGranted),
        (false, nil, .notGranted),
    ])
    func resolve(live: Bool, tcc: PermissionStatus?, expected: PermissionStatus) {
        #expect(PermissionStatus.resolve(live: live, tcc: tcc) == expected)
    }

    @Test("Reading real statuses doesn't crash or hang outside an app")
    func realStatuses() {
        let start = Date()
        for permission in Permission.allDraggable { _ = permission.currentStatus() }
        #expect(Date().timeIntervalSince(start) < 5)
    }
}

@Suite("Permission center")
@MainActor
struct PermissionCenterTests {
    @Test("Caches statuses until refreshed")
    func refresh() {
        let state = StatusSwitch(.notGranted)
        let permission = Permission(id: "center-\(UUID())", title: "T", summary: "", systemImage: "star", tint: .red,
                                    settingsAnchor: "Privacy_T") { state.status }
        let center = PermissionCenter.shared
        #expect(center.status(of: permission) == .notGranted)
        state.status = .granted
        #expect(center.status(of: permission) == .notGranted)
        center.refresh()
        #expect(center.status(of: permission) == .granted)
    }
}

@Suite("Relauncher")
@MainActor
struct RelauncherTests {
    @Test("The resume flag is read once")
    func resumeFlag() throws {
        let suite = "TrustMeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Relauncher.consumeResumeFlag(in: defaults) == false)
        Relauncher.setResumeFlag(in: defaults)
        #expect(Relauncher.consumeResumeFlag(in: defaults) == true)
        #expect(Relauncher.consumeResumeFlag(in: defaults) == false)
    }
}
