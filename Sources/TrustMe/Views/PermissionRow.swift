import SwiftUI

/// One permission: a line icon, its name, a status-aware explanation and a
/// trailing control (``PermissionButton`` unless you supply your own).
public struct PermissionRow<Trailing: View>: View {
    let permission: Permission
    let detail: String?
    let trailing: Trailing
    let flow: PermissionFlow

    public init(
        _ permission: Permission,
        detail: String? = nil,
        flow: PermissionFlow = .shared,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.permission = permission
        self.detail = detail
        self.flow = flow
        self.trailing = trailing()
    }

    public var body: some View {
        let status = PermissionCenter.shared.status(of: permission)
        HStack(spacing: 14) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(status == .granted ? TrustMeTheme.tertiaryText : TrustMeTheme.secondaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TrustMeTheme.primaryText)
                Text(detail ?? defaultDetail(status))
                    .font(.system(size: 12))
                    .foregroundStyle(TrustMeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 16)
            trailing.fixedSize()
        }
        .padding(.vertical, 13)
        .animation(TrustMeTheme.quick, value: status)
    }

    private func defaultDetail(_ status: PermissionStatus) -> String {
        let app = flow.app?.name ?? AppIdentity.current.name
        if status == .needsRelaunch { return "Turned on. Relaunch \(app) to apply it." }
        if status == .notGranted, permission.isPromptBased, !permission.canRequest() {
            return "Turned off earlier. Turn on \(app) under \(permission.title) in System Settings."
        }
        if status != .granted, flow.activePermission == permission {
            return "Finish in System Settings to turn it on."
        }
        return permission.summary
    }
}

public extension PermissionRow where Trailing == PermissionButton {
    init(_ permission: Permission, detail: String? = nil, flow: PermissionFlow = .shared) {
        self.init(permission, detail: detail, flow: flow) { PermissionButton(permission, flow: flow) }
    }
}
