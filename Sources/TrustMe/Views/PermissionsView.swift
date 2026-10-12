import AppKit
import SwiftUI

/// A complete permissions screen that lays itself out from the list it's
/// given: explanation, one row per permission, and a footer whose
/// Continue button unlocks once every required permission is granted.
///
/// Embed it in your own window, or let ``PermissionsWindow`` host it.
public struct PermissionsView: View {
    let permissions: [Permission]
    let optional: Set<Permission>
    let title: String?
    let message: String?
    let continueTitle: String
    let skipTitle: String?
    let showsAppIcon: Bool
    let flow: PermissionFlow
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    /// - Parameters:
    ///   - permissions: What the app needs, in display order.
    ///   - optional: Permissions that don't block Continue.
    ///   - title: Defaults to "Grant permissions".
    ///   - message: Defaults to a short explanation naming the app.
    ///   - skipTitle: Shown while something is missing; `nil` hides it.
    public init(
        _ permissions: [Permission],
        optional: Set<Permission> = [],
        title: String? = nil,
        message: String? = nil,
        continueTitle: String = "Continue",
        skipTitle: String? = "Skip for now",
        showsAppIcon: Bool = true,
        flow: PermissionFlow = .shared,
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.permissions = permissions
        self.optional = optional
        self.title = title
        self.message = message
        self.continueTitle = continueTitle
        self.skipTitle = skipTitle
        self.showsAppIcon = showsAppIcon
        self.flow = flow
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    private var app: AppIdentity { flow.app ?? .current }

    public var body: some View {
        let center = PermissionCenter.shared
        let granted = permissions.filter { center.status(of: $0) == .granted }
        let requiredMissing = permissions.contains { !optional.contains($0) && center.status(of: $0) != .granted }

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if showsAppIcon {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .padding(.bottom, 18)
                }
                Text(title ?? "Grant permissions")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(TrustMeTheme.primaryText)
                Text(message ?? defaultMessage)
                    .font(.system(size: 13.5))
                    .lineSpacing(2)
                    .foregroundStyle(TrustMeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    Hairline()
                    ForEach(permissions) { permission in
                        PermissionRow(permission, flow: flow)
                        Hairline()
                    }
                }
                .padding(.top, 28)
            }
            .frame(width: 500, alignment: .leading)
            .padding(.top, showsAppIcon ? 52 : 72)
            .padding(.bottom, 44)
            .padding(.horizontal, 60)

            Hairline()
            HStack(spacing: 10) {
                Text("\(granted.count) of \(permissions.count) granted")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(TrustMeTheme.tertiaryText)
                    .contentTransition(.numericText())
                Spacer()
                if let skipTitle, requiredMissing {
                    Button(skipTitle) { (onSkip ?? onContinue)() }
                        .buttonStyle(.trustMeLink)
                }
                Button(continueTitle, action: onContinue)
                    .buttonStyle(.trustMePrimary)
                    .disabled(requiredMissing)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(TrustMeTheme.quick, value: granted.count)
    }

    private var defaultMessage: String {
        let needs = "\(app.name) needs \(permissions.count == 1 ? "this" : "these") to work."
        // Only mention dragging when something on the list is granted that way.
        guard permissions.contains(where: { !$0.isPromptBased }) else { return "\(needs) Click Allow to turn them on." }
        return "\(needs) Click Allow, then drag \(app.name) into the list System Settings opens."
    }
}

/// Hosts ``PermissionsView`` in a dark glass window.
///
/// ```swift
/// PermissionsWindow.show([.accessibility, .screenRecording]) { allGranted in
///     startApp()
/// }
/// ```
@MainActor
public final class PermissionsWindow: NSObject, NSWindowDelegate {
    /// The window currently on screen, if any.
    public private(set) static var current: PermissionsWindow?

    public let window: NSWindow
    private let permissions: [Permission]
    private let optional: Set<Permission>
    private let onFinish: (_ allGranted: Bool) -> Void

    /// Shows the window, replacing any that's already open.
    /// - Parameter onFinish: Called once, when the user continues, skips or
    ///   closes the window. `allGranted` covers required permissions only.
    @discardableResult
    public static func show(
        _ permissions: [Permission],
        optional: Set<Permission> = [],
        title: String? = nil,
        message: String? = nil,
        continueTitle: String = "Continue",
        skipTitle: String? = "Skip for now",
        showsAppIcon: Bool = true,
        flow: PermissionFlow = .shared,
        onFinish: @escaping (_ allGranted: Bool) -> Void = { _ in }
    ) -> PermissionsWindow {
        Relauncher.install()
        current?.close()

        var controller: PermissionsWindow?
        let view = PermissionsView(
            permissions,
            optional: optional,
            title: title,
            message: message,
            continueTitle: continueTitle,
            skipTitle: skipTitle,
            showsAppIcon: showsAppIcon,
            flow: flow,
            onContinue: { controller?.finish() },
            onSkip: { controller?.finish() }
        )
        let hosting = NSHostingController(rootView: view.background(WindowGlass()).preferredColorScheme(.dark))
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()

        let instance = PermissionsWindow(window: window, permissions: permissions, optional: optional, onFinish: onFinish)
        controller = instance
        window.delegate = instance
        current = instance

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return instance
    }

    private init(window: NSWindow, permissions: [Permission], optional: Set<Permission>, onFinish: @escaping (Bool) -> Void) {
        self.window = window
        self.permissions = permissions
        self.optional = optional
        self.onFinish = onFinish
    }

    public func close() { window.close() }

    private func finish() { window.close() }

    public func windowWillClose(_ notification: Notification) {
        guard Self.current === self else { return }
        Self.current = nil
        let center = PermissionCenter.shared
        onFinish(permissions.allSatisfy { optional.contains($0) || center.status(of: $0) == .granted })
    }
}

/// Behind-window blur under a dark smoke: the window reads as glass over the
/// desktop while text keeps its contrast.
struct WindowGlass: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 0)
            TrustMeTheme.window.opacity(0.8)
            LinearGradient(colors: [.white.opacity(0.04), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}
