import SwiftUI

/// The action for one permission, chosen from its live status: Allow (starts
/// the drag flow), Relaunch (granted, waiting on a restart) or a quiet
/// "Granted" check. Drop it into your own onboarding as-is.
public struct PermissionButton: View {
    let permission: Permission
    let flow: PermissionFlow
    let small: Bool

    public init(_ permission: Permission, flow: PermissionFlow = .shared, small: Bool = true) {
        self.permission = permission
        self.flow = flow
        self.small = small
    }

    public var body: some View {
        Group {
            switch PermissionCenter.shared.status(of: permission) {
            case .granted:
                GrantedLabel()
            case .needsRelaunch:
                Button("Relaunch") { Relauncher.relaunch() }
                    .buttonStyle(.trustMePrimary(small: small))
            case .notGranted:
                Button(flow.activePermission == permission ? "Open settings" : "Allow") { flow.authorize(permission) }
                    .buttonStyle(.trustMeSecondary(small: small))
            case .unknown:
                Button("Open settings") { flow.authorize(permission) }
                    .buttonStyle(.trustMeSecondary(small: small))
            }
        }
        .animation(TrustMeTheme.quick, value: PermissionCenter.shared.status(of: permission))
    }
}

/// Green check and a quiet label.
public struct GrantedLabel: View {
    var title: String

    public init(_ title: String = "Granted") { self.title = title }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(TrustMeTheme.green)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(TrustMeTheme.secondaryText)
        }
        .frame(height: 28)
    }
}
