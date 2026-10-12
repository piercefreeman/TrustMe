import AppKit
import Observation
import SwiftUI

/// The app bundle the user drags into System Settings.
public struct AppIdentity: Sendable {
    public var url: URL
    public var name: String
    public var icon: NSImage

    public init(url: URL, name: String, icon: NSImage) {
        self.url = url
        self.name = name
        self.icon = icon
    }

    /// The running app. When launched outside a `.app` bundle (e.g. `swift run`)
    /// the drag has nothing meaningful to grant, so build an app bundle.
    @MainActor public static var current: AppIdentity {
        let bundle = Bundle.main
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ProcessInfo.processInfo.processName
        return AppIdentity(url: bundle.bundleURL, name: name, icon: NSApp.applicationIconImage)
    }

    public var isAppBundle: Bool { url.pathExtension == "app" }
}

/// Drives the drag-to-authorize flow: opens the right System Settings pane,
/// then floats a glass panel beside it that the user drags the app out of.
///
/// ```swift
/// PermissionFlow.shared.authorize(.accessibility)
/// ```
@MainActor
@Observable
public final class PermissionFlow {
    public static let shared = PermissionFlow()

    /// The app being authorized. Defaults to the running app.
    public var app: AppIdentity?
    /// Close the panel automatically once the permission is detected.
    @ObservationIgnored public var dismissesOnGrant = true
    /// Bring the app back to the front after a successful grant.
    @ObservationIgnored public var activatesAppOnGrant = true
    /// Called when a permission flips to granted during a flow.
    @ObservationIgnored public var onGranted: ((Permission) -> Void)?

    public private(set) var activePermission: Permission?

    @ObservationIgnored private var panel: GuidePanel?
    @ObservationIgnored private var model: GuideModel?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastSettingsFrame: CGRect?
    @ObservationIgnored private var settingsStableSince: Date?
    @ObservationIgnored private var missingSince: Date?
    @ObservationIgnored private var hasPresented = false

    public init() {
        Relauncher.install()
    }

    /// Starts the flow for `permission`. The panel stays hidden until the
    /// System Settings window has settled, then appears in place beside it.
    public func authorize(_ permission: Permission) {
        dismiss(animated: false)

        let model = GuideModel(permission: permission, app: app ?? .current)
        model.onClose = { [weak self] in self?.dismiss() }
        self.model = model
        self.activePermission = permission
        startedAt = Date()
        lastSettingsFrame = nil
        settingsStableSince = nil
        missingSince = nil
        hasPresented = false

        let hosting = FirstMouseHostingView(rootView: DragGuideView(model: model))
        hosting.layoutSubtreeIfNeeded()
        let panel = GuidePanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize))
        panel.contentView = hosting
        self.panel = panel

        NSWorkspace.shared.open(permission.settingsURL)

        tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    public func dismiss() { dismiss(animated: true) }

    private func dismiss(animated: Bool) {
        tick?.invalidate()
        tick = nil
        activePermission = nil
        guard let panel, let model else { return }
        self.panel = nil
        self.model = nil

        guard animated, panel.isVisible else { panel.orderOut(nil); return }
        model.isPresented = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(CGPoint(x: panel.frame.minX, y: panel.frame.minY - 12))
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    // MARK: - Frame loop

    @ObservationIgnored private var statusCheckCounter = 0

    private func step() {
        guard let panel, let model else { return }

        statusCheckCounter += 1
        if statusCheckCounter % 20 == 0 { checkStatus(model) }

        let settings = SystemSettingsWindow.currentFrame()
        // Only float over System Settings while the user is looking at it:
        // "drag into the list above" means nothing with Settings out of sight.
        let settingsInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == SystemSettingsWindow.bundleIdentifier
            || model.phase == .dragging

        if !hasPresented {
            if let settings, settingsInFront {
                // Wait until System Settings has finished launching, resizing
                // and navigating: its frame must hold still before we appear.
                if settings != lastSettingsFrame {
                    lastSettingsFrame = settings
                    settingsStableSince = Date()
                    return
                }
                guard let since = settingsStableSince, Date().timeIntervalSince(since) > 0.3 else { return }
                present(panel, model, beside: settings)
            }
            return
        }

        guard model.phase != .granted else { return }

        if let settings {
            missingSince = nil
            if settings != lastSettingsFrame {
                lastSettingsFrame = settings
                let (origin, edge) = GuidePlacement.place(panelSize: panel.frame.size, beside: settings)
                panel.setFrameOrigin(origin)
                if edge != model.edge { model.edge = edge }
            }
            if settingsInFront, !panel.isVisible {
                panel.orderFrontRegardless()
            } else if !settingsInFront, panel.isVisible {
                panel.orderOut(nil)
            }
        } else if lastSettingsFrame != nil {
            // Settings closed, minimized, or moved to another Space.
            let since = missingSince ?? Date()
            missingSince = since
            if Date().timeIntervalSince(since) > 0.6 {
                if NSRunningApplication.runningApplications(withBundleIdentifier: SystemSettingsWindow.bundleIdentifier).isEmpty {
                    dismiss()
                } else if panel.isVisible {
                    panel.orderOut(nil)
                }
            }
        }
    }

    private func present(_ panel: GuidePanel, _ model: GuideModel, beside settings: CGRect) {
        hasPresented = true
        let (target, edge) = GuidePlacement.place(panelSize: panel.frame.size, beside: settings)
        model.edge = edge

        // Appear exactly where it belongs: a short fade while the content
        // scales in, with no travel across the screen.
        panel.alphaValue = 0
        panel.setFrameOrigin(target)
        lastSettingsFrame = settings
        panel.orderFrontRegardless()
        model.isPresented = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func checkStatus(_ model: GuideModel) {
        guard model.phase != .granted, model.phase != .needsRelaunch else { return }
        let status = model.permission.currentStatus()
        guard status == .granted || status == .needsRelaunch else { return }
        PermissionCenter.shared.refresh()
        let permission = model.permission
        onGranted?(permission)

        // Stay up with a Relaunch button until the app restarts.
        guard status == .granted else { model.phase = .needsRelaunch; return }
        model.phase = .granted

        guard dismissesOnGrant else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model === model else { return }
                self.dismiss()
                if self.activatesAppOnGrant { NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }
}

/// Borderless, non-activating, transparent panel that floats above System
/// Settings without stealing focus from it.
final class GuidePanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
