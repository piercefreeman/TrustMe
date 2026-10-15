import SwiftUI
@testable import TrustMe

/// TrustMe's ``PermissionsView``, laid out identically but driven by
/// ``DemoState`` instead of the live permission status.
struct PermissionsPane: View {
    let state: DemoState
    let app: AppIdentity

    static let permissions: [Permission] = [
        .accessibility, .screenRecording, .inputMonitoring, .fullDiskAccess, .appManagement, .developerTools,
    ]
    static let optional: Set<String> = [Permission.appManagement.id, Permission.developerTools.id]

    var body: some View {
        let permissions = Self.permissions
        let grantedCount = permissions.filter { state.granted.contains($0.id) }.count
        let requiredMissing = permissions.contains { !Self.optional.contains($0.id) && !state.granted.contains($0.id) }

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .padding(.bottom, 18)
                Text("Grant permissions")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(TrustMeTheme.primaryText)
                Text("\(app.name) needs these to work. Click Allow, then drag \(app.name) into the list System Settings opens.")
                    .font(.system(size: 13.5))
                    .lineSpacing(2)
                    .foregroundStyle(TrustMeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    Hairline()
                    ForEach(permissions) { permission in
                        row(permission)
                        Hairline()
                    }
                }
                .padding(.top, 28)
            }
            .frame(width: 500, alignment: .leading)
            .padding(.top, 52)
            .padding(.bottom, 44)
            .padding(.horizontal, 60)

            Hairline()
            HStack(spacing: 10) {
                Text("\(grantedCount) of \(permissions.count) granted")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(TrustMeTheme.tertiaryText)
                    .contentTransition(.numericText())
                Spacer()
                if requiredMissing {
                    Button("Skip for now") {}.buttonStyle(.trustMeLink)
                }
                Button("Done") {}
                    .buttonStyle(.trustMePrimary)
                    .disabled(requiredMissing)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(TrustMeTheme.quick, value: grantedCount)
    }

    private func row(_ permission: Permission) -> some View {
        let granted = state.granted.contains(permission.id)
        let active = state.activeID == permission.id && !granted
        return HStack(spacing: 14) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(granted ? TrustMeTheme.tertiaryText : TrustMeTheme.secondaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TrustMeTheme.primaryText)
                Text(active ? "Finish in System Settings to turn it on." : permission.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(TrustMeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 16)
            Group {
                if granted {
                    GrantedLabel()
                } else {
                    Button(active ? "Open settings" : "Allow") {}
                        .buttonStyle(.trustMeSecondary(small: true))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(state.pressedID == permission.id ? 0.1 : 0))
                        }
                        .anchor("allow.\(permission.id)")
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 13)
        .animation(TrustMeTheme.quick, value: granted)
        .animation(TrustMeTheme.quick, value: active)
    }
}
