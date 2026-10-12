import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class GuideModel {
    /// `stalled`: dropped a while ago but the grant never showed up — usually
    /// a stale list entry from an older build or a switch left off.
    enum Phase: Equatable { case waiting, dragging, dropped, stalled, needsRelaunch, granted }

    let permission: Permission
    let app: AppIdentity
    var phase: Phase = .waiting
    var edge: GuideEdge = .below
    var isPresented = false
    var isHovering = false
    var isPressed = false
    var showsClose = false
    /// Freezes ambient animation (sheen, cue motion) for still renders.
    var isStill = false
    @ObservationIgnored var onClose: () -> Void = {}

    init(permission: Permission, app: AppIdentity) {
        self.permission = permission
        self.app = app
    }
}

/// The floating panel: a single pane of glass that *is* the app — pick it
/// up and drop it into System Settings.
struct DragGuideView: View {
    @Bindable var model: GuideModel
    @State private var dragImage: NSImage?

    static let width: CGFloat = 360
    static let inset: CGFloat = 10 // room for the close button to overhang
    static let radius: CGFloat = 20

    private var granted: Bool { model.phase == .granted }
    private var allowed: Bool { granted || model.phase == .needsRelaunch }
    private var stalled: Bool { model.phase == .stalled }

    var body: some View {
        band
            .overlay(alignment: .topLeading) { closeButton }
            .padding(Self.inset)
            .onHover { model.showsClose = $0 }
            .scaleEffect(model.isPresented ? 1 : 0.9)
            .opacity(model.isPresented ? 1 : 0)
            .blur(radius: model.isPresented ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.isPresented)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.phase)
            .onAppear { dragImage = DragChip.render(app: model.app) }
    }

    private var band: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return HStack(spacing: 12) {
            Image(nsImage: model.app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1.5)
                .overlay(alignment: .bottomTrailing) {
                    if allowed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.systemGreen)
                            .offset(x: 4, y: 4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.app.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            DirectionCue(edge: model.edge, phase: model.phase, hovering: model.isHovering, still: model.isStill)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(width: Self.width, height: 66)
        .glassSurface(cornerRadius: Self.radius)
        .overlay {
            if model.phase == .waiting, !model.isStill { Sheen(cornerRadius: Self.radius) }
        }
        .overlay {
            // State is carried by a soft rim glow, never by tinting the glass.
            if allowed || stalled {
                let color = allowed ? Color.systemGreen : Color.systemOrange
                shape.strokeBorder(color.opacity(0.55), lineWidth: 1)
                    .shadow(color: color.opacity(0.2), radius: 6)
                    .transition(.opacity)
            }
        }
        .overlay {
            // Ghost outline left behind while the app is "in flight".
            shape.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.white.opacity(0.5))
                .opacity(model.phase == .dragging ? 1 : 0)
        }
        .opacity(model.phase == .dragging ? 0.5 : 1)
        .scaleEffect(model.isPressed ? 0.98 : (model.isHovering && !allowed ? 1.015 : 1))
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: model.isPressed)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.isHovering)
        .overlay {
            if !allowed, let dragImage {
                AppDragSource(
                    appURL: model.app.url,
                    dragImage: dragImage,
                    onHover: { model.isHovering = $0 },
                    onPress: { model.isPressed = $0 },
                    onDragBegan: { model.phase = .dragging },
                    onDragEnded: { dropped in
                        guard model.phase == .dragging else { return }
                        model.phase = dropped ? .dropped : .waiting
                        guard dropped else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            if model.phase == .dropped { model.phase = .stalled }
                        }
                    }
                )
            }
        }
    }

    private var caption: String {
        return switch model.phase {
        case .waiting, .dragging: "Drag into the list \(model.edge.direction) to allow"
        case .dropped: "Approve with Touch ID or your password"
        case .stalled: "Not showing up yet.\nSelect it, click \u{2212}, then drag again."
        case .needsRelaunch: "Allowed. Relaunch to apply it."
        case .granted: "\(model.permission.title) allowed"
        }
    }

    /// Notification Center–style close: a small, solid disc on the corner,
    /// shown on hover (and whenever the flow is stuck).
    private var closeButton: some View {
        let visible = !granted && (model.showsClose || stalled || model.phase == .needsRelaunch)
        return Button(action: model.onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(red: 0.23, green: 0.23, blue: 0.235).opacity(0.95)))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(5) // larger hit target
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: -11, y: -11)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.8)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: visible)
        .onHover { inside in if inside { NSCursor.arrow.set() } }
        .help("Close")
    }
}

/// The trailing status glyph: a bare arrow drifting toward the list while
/// waiting, a spinner while System Settings authenticates, a warning when
/// stuck. No container — it's a hint, not a button.
struct DirectionCue: View {
    var edge: GuideEdge
    var phase: GuideModel.Phase
    var hovering: Bool
    var still: Bool

    var body: some View {
        Group {
            switch phase {
            case .waiting, .dragging:
                TimelineView(.animation(paused: still || hovering)) { context in
                    // Ease toward the list and back every 2.4s.
                    let t = context.date.timeIntervalSinceReferenceDate
                    let wave = still || hovering ? 1 : (1 - cos(t / 2.4 * 2 * .pi)) / 2
                    Image(systemName: arrow)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.45 + 0.4 * wave))
                        .offset(x: direction.width * 3 * wave, y: direction.height * 3 * wave)
                }
                .opacity(phase == .dragging ? 0 : 1)
            case .dropped:
                Spinner(still: still)
            case .stalled:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.systemOrange)
            case .needsRelaunch:
                Button("Relaunch") { Relauncher.relaunch() }
                    .buttonStyle(.trustMePrimary(small: true))
                    .fixedSize()
            case .granted:
                EmptyView()
            }
        }
        .frame(minWidth: 22, minHeight: 22)
        .transition(.opacity)
    }

    private var arrow: String {
        switch edge {
        case .right: "arrow.left"
        case .left: "arrow.right"
        default: "arrow.up"
        }
    }

    private var direction: CGSize {
        switch edge {
        case .right: CGSize(width: -1, height: 0)
        case .left: CGSize(width: 1, height: 0)
        default: CGSize(width: 0, height: -1)
        }
    }
}

/// A small, bright activity arc; the system spinner reads as disabled on glass.
struct Spinner: View {
    var still: Bool

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let angle = still ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                .rotationEffect(.degrees(angle))
                .frame(width: 13, height: 13)
        }
    }
}

extension Color {
    static let systemGreen = Color(red: 0.19, green: 0.82, blue: 0.35)  // #30D158
    static let systemOrange = Color(red: 1.0, green: 0.62, blue: 0.04)  // #FF9F0A
}

/// The image under the cursor while dragging: the app icon with a name
/// label, as Finder would show it.
struct DragChip: View {
    let app: AppIdentity

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(nsColor: .selectedContentBackgroundColor)))
        }
        .padding(8)
    }

    @MainActor
    static func render(app: AppIdentity) -> NSImage? {
        let renderer = ImageRenderer(content: DragChip(app: app))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}

/// An occasional soft glint across the glass, inviting a pickup.
struct Sheen: View {
    var cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = 4.0
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / 1.4
            GeometryReader { proxy in
                let width = proxy.size.width
                // Taller than the band so the rotated edges never show.
                LinearGradient(colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.28, height: proxy.size.height * 3)
                    .rotationEffect(.degrees(20))
                    .position(x: -width * 0.3 + min(progress, 1) * width * 1.6, y: proxy.size.height / 2)
                    .blendMode(.plusLighter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}
