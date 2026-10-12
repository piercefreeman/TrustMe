import SwiftUI

/// TrustMe's visual language: near-monochrome dark glass, hairlines, one
/// bright control per screen, green only for "granted".
public enum TrustMeTheme {
    public static let window = Color(red: 0.115, green: 0.115, blue: 0.122)
    public static let primaryText = Color.white.opacity(0.94)
    public static let secondaryText = Color.white.opacity(0.56)
    public static let tertiaryText = Color.white.opacity(0.34)
    public static let line = Color.white.opacity(0.09)
    public static let green = Color(red: 0.30, green: 0.82, blue: 0.47)
    static let quick = Animation.easeOut(duration: 0.16)
}

/// A 1pt divider in the theme's line color.
public struct Hairline: View {
    public init() {}
    public var body: some View { Rectangle().fill(TrustMeTheme.line).frame(height: 1) }
}

/// Filled white: the one bright thing on a screen.
public struct TrustMePrimaryButtonStyle: ButtonStyle {
    public var small = false
    public func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, small: small) }

    private struct Styled: View {
        let configuration: Configuration
        let small: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: small ? 12 : 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(isEnabled ? 0.9 : 0.45))
                .padding(.horizontal, small ? 12 : 16)
                .frame(height: small ? 28 : 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(!isEnabled ? 0.28 : configuration.isPressed ? 0.75 : hovering ? 0.84 : 0.93))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(TrustMeTheme.quick, value: hovering)
        }
    }
}

/// Outlined with a hairline.
public struct TrustMeSecondaryButtonStyle: ButtonStyle {
    public var small = false
    public func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, small: small) }

    private struct Styled: View {
        let configuration: Configuration
        let small: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: small ? 12 : 13))
                .foregroundStyle(TrustMeTheme.primaryText.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, small ? 11 : 14)
                .frame(height: small ? 28 : 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.1 : hovering ? 0.07 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(TrustMeTheme.quick, value: hovering)
        }
    }
}

/// Bare text that brightens on hover.
public struct TrustMeLinkButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(hovering ? TrustMeTheme.primaryText : TrustMeTheme.secondaryText)
                .padding(.horizontal, 4)
                .frame(height: 28)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(TrustMeTheme.quick, value: hovering)
        }
    }
}

public extension ButtonStyle where Self == TrustMePrimaryButtonStyle {
    static var trustMePrimary: Self { .init() }
    static func trustMePrimary(small: Bool) -> Self { .init(small: small) }
}

public extension ButtonStyle where Self == TrustMeSecondaryButtonStyle {
    static var trustMeSecondary: Self { .init() }
    static func trustMeSecondary(small: Bool) -> Self { .init(small: small) }
}

public extension ButtonStyle where Self == TrustMeLinkButtonStyle {
    static var trustMeLink: Self { .init() }
}
