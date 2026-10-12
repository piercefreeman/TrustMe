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
        let all = Permission.all
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
        let relaunching = Permission.all.filter(\.requiresRelaunch).map(\.id)
        #expect(Set(relaunching) == ["screen-recording", "input-monitoring"])
    }

    @Test("Camera and Microphone are asked for with the system prompt; the rest are dragged")
    func kinds() {
        #expect(Set(Permission.allPromptBased.map(\.id)) == ["camera", "microphone"])
        let promptBased = Permission.allPromptBased.map(\.isPromptBased)
        let dragged = Permission.allDraggable.map(\.isPromptBased)
        #expect(!promptBased.contains(false))
        #expect(!dragged.contains(true))
        #expect(Permission.all.count == Permission.allDraggable.count + Permission.allPromptBased.count)
        // Drag-based permissions never claim they can prompt.
        #expect(!Permission.allDraggable.contains { $0.canRequest() })
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

/// Records what a prompt-based permission was asked to do.
final class PromptRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests = 0
    private var _answered = false
    var requests: Int { lock.withLock { _requests } }
    var answered: Bool { lock.withLock { _answered } }
    func answer() { lock.withLock { _requests += 1; _answered = true } }
}

@Suite("Prompt-based permissions")
@MainActor
struct PromptTests {
    func permission(_ recorder: PromptRecorder, granting: Bool) -> Permission {
        Permission(
            id: "prompt-\(UUID())", title: "Prompt", summary: "", systemImage: "camera", tint: .green,
            settingsAnchor: "Privacy_Camera",
            check: { recorder.answered && granting ? .granted : .notGranted },
            canRequest: { !recorder.answered },
            request: { recorder.answer() }
        )
    }

    @Test("Allow shows the prompt, then the answer sticks")
    func prompts() async throws {
        let recorder = PromptRecorder()
        let permission = permission(recorder, granting: true)
        #expect(permission.isPromptBased)
        #expect(permission.canRequest())

        var granted: [Permission] = []
        let flow = PermissionFlow()
        flow.onGranted = { granted.append($0) }
        flow.authorize(permission)

        for _ in 0..<100 where recorder.requests == 0 || granted.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.requests == 1)
        #expect(granted == [permission])
        #expect(!permission.canRequest())
        #expect(PermissionCenter.shared.status(of: permission) == .granted)
    }

    @Test("A refused prompt offers System Settings instead")
    func refused() {
        let recorder = PromptRecorder()
        recorder.answer()
        let permission = permission(recorder, granting: false)
        #expect(!permission.canRequest())
        #expect(PermissionButton(permission).allowTitle == "Open settings")
    }

    @Test("A fresh prompt-based permission offers Allow")
    func fresh() {
        let permission = permission(PromptRecorder(), granting: true)
        #expect(PermissionButton(permission).allowTitle == "Allow")
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
