import AppKit
import Observation

/// Observable cache of permission statuses. Views that read
/// ``status(of:)`` re-render automatically when a status changes.
@MainActor
@Observable
public final class PermissionCenter {
    public static let shared = PermissionCenter()

    private var revision = 0
    @ObservationIgnored private var cache: [Permission.ID: PermissionStatus] = [:]
    @ObservationIgnored private var known: [Permission.ID: Permission] = [:]
    @ObservationIgnored private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { PermissionCenter.shared.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { PermissionCenter.shared.refresh() }
        }
    }

    public func status(of permission: Permission) -> PermissionStatus {
        _ = revision
        if let cached = cache[permission.id] { return cached }
        let status = permission.currentStatus()
        cache[permission.id] = status
        known[permission.id] = permission
        return status
    }

    /// Re-reads every permission that has been queried so far.
    /// - Parameter force: Re-render observers even if no status changed, e.g.
    ///   when a prompt was answered and what the UI offers changes with it.
    public func refresh(force: Bool = false) {
        var changed = false
        for (id, permission) in known {
            let status = permission.currentStatus()
            if cache[id] != status {
                cache[id] = status
                changed = true
            }
        }
        if changed || force { revision &+= 1 }
    }
}
