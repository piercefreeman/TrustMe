import AppKit
import SwiftUI

public struct AlertButton: Hashable, Sendable {
    public let title: String
    public let isDefault: Bool

    public init(_ title: String, isDefault: Bool = false) {
        self.title = title
        self.isDefault = isDefault
    }
}

/// A recreation of a macOS Sequoia alert (the TCC and authorization prompts):
/// centered icon, bold title, small message, full-width rounded buttons.
public struct SystemAlert<Accessory: View>: View {
    let icon: NSImage
    let badge: String?
    let badgeTint: Color
    let title: String
    let message: String?
    let buttons: [AlertButton]
    /// Blur what's drawn beneath in the same window instead of behind it.
    let withinWindow: Bool
    let accessory: Accessory

    @Environment(\.colorScheme) private var scheme

    public static var width: CGFloat { 260 }
    static var radius: CGFloat { 12 }

    public init(
        icon: NSImage,
        badge: String? = nil,
        badgeTint: Color = .blue,
        title: String,
        message: String?,
        buttons: [AlertButton],
        withinWindow: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.badge = badge
        self.badgeTint = badgeTint
        self.title = title
        self.message = message
        self.buttons = buttons
        self.withinWindow = withinWindow
        self.accessory = accessory()
    }

    private var dark: Bool { scheme == .dark }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(spacing: 0) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(badgeTint.gradient))
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .offset(x: 4, y: 4)
                    }
                }
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.top, 14)
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .padding(.top, 7)
            }
            accessory
            buttonStack.padding(.top, 18)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: Self.width)
        .background {
            ZStack {
                AlertMaterial(withinWindow: withinWindow, cornerRadius: Self.radius)
                shape.fill(dark ? Color(white: 0.17).opacity(0.55) : Color.white.opacity(0.35))
            }
        }
        .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08), lineWidth: 0.5))
        .overlay(shape.strokeBorder(Color.black.opacity(dark ? 0.6 : 0.12), lineWidth: 0.5).padding(-0.5))
        .shadow(color: .black.opacity(dark ? 0.45 : 0.25), radius: 24, y: 12)
    }

    /// Side by side when two short titles fit, stacked otherwise (like NSAlert).
    @ViewBuilder private var buttonStack: some View {
        let horizontal = buttons.count == 2 && buttons.allSatisfy { $0.title.count <= 14 }
        if horizontal {
            HStack(spacing: 8) { ForEach(buttons, id: \.self, content: button) }
        } else {
            VStack(spacing: 8) { ForEach(buttons, id: \.self, content: button) }
        }
    }

    private func button(_ spec: AlertButton) -> some View {
        Text(spec.title)
            .font(.system(size: 13))
            .lineLimit(1)
            .foregroundStyle(spec.isDefault ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(spec.isDefault ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.07)))
            )
            .shadow(color: .black.opacity(spec.isDefault ? 0.15 : 0), radius: 1, y: 0.5)
    }
}

public extension SystemAlert where Accessory == EmptyView {
    init(icon: NSImage, badge: String? = nil, badgeTint: Color = .blue, title: String, message: String?, buttons: [AlertButton], withinWindow: Bool = true) {
        self.init(icon: icon, badge: badge, badgeTint: badgeTint, title: title, message: message, buttons: buttons, withinWindow: withinWindow) { EmptyView() }
    }
}

/// Alert vibrancy with a rounded mask, so blur and shadow share a silhouette.
struct AlertMaterial: NSViewRepresentable {
    var withinWindow: Bool
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = .popover
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.blendingMode = withinWindow ? .withinWindow : .behindWindow
        let edge = cornerRadius * 2 + 1
        let mask = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        mask.resizingMode = .stretch
        view.maskImage = mask
    }
}
