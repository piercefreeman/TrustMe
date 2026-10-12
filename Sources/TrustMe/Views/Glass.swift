import AppKit
import SwiftUI

/// A behind-window blur with a proper rounded mask, so the window shadow and
/// the blur share the same silhouette.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.maskImage = cornerRadius > 0 ? .roundedMask(radius: cornerRadius) : nil
    }
}

extension NSImage {
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Glass surface: Liquid Glass on macOS 26+. Earlier systems get a
/// recreation: blur under a neutral smoke, a hairline rim lit from above,
/// a faint inner glow and a specular sheen.
public struct GlassSurface: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?
    public var blendingMode: NSVisualEffectView.BlendingMode

    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint?.opacity(0.12)), in: shape)
        } else {
            let dark = colorScheme == .dark
            content
                .background {
                    ZStack {
                        // Fading a blur view reveals unblurred content, so keep it opaque.
                        VisualEffectBlur(material: .fullScreenUI, blendingMode: blendingMode, cornerRadius: cornerRadius)
                        // Neutral smoke so saturated backdrops don't stain the glass.
                        shape.fill(dark ? Color.black.opacity(0.3) : Color.white.opacity(0.25))
                        if let tint { shape.fill(tint.opacity(0.06)) }
                        // Specular sheen: light pooling at the top edge.
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(dark ? 0.10 : 0.35), location: 0),
                                    .init(color: .white.opacity(0), location: 0.45),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        // Faint inner glow hugging the edge, like light inside thick glass.
                        shape.stroke(.white.opacity(dark ? 0.07 : 0.4), lineWidth: 6)
                            .blur(radius: 5)
                            .clipShape(shape)
                    }
                }
                .overlay {
                    // Hairline rim: catches light on top, nearly vanishes on the
                    // sides, with a faint bounce along the bottom.
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.40), location: 0.0),
                                .init(color: .white.opacity(0.06), location: 0.4),
                                .init(color: .white.opacity(0.06), location: 0.75),
                                .init(color: .white.opacity(0.14), location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    .blendMode(.plusLighter)
                }
                .overlay {
                    shape.strokeBorder(.black.opacity(dark ? 0.35 : 0.08), lineWidth: 0.5).padding(-0.5)
                }
        }
    }
}

public extension View {
    /// Wraps the view in a glass surface.
    func glassSurface(
        cornerRadius: CGFloat = 22,
        tint: Color? = nil,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, blendingMode: blendingMode))
    }
}
