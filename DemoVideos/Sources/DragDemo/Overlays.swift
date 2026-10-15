import AppKit
import DemoSupport
import SwiftUI

/// The scripted pointer, the app chip it carries, and click ripples.
struct PointerOverlay: View {
    let state: DemoState
    let chip: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(state.clicks) { click in
                ClickRipple().position(click.point)
            }
            if let chip, state.chipVisible {
                Image(nsImage: chip)
                    .position(state.cursor)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if state.cursorVisible {
                let cursor = nsCursor
                let size = cursor.image.size
                Image(nsImage: cursor.image)
                    .position(x: state.cursor.x - cursor.hotSpot.x + size.width / 2, y: state.cursor.y - cursor.hotSpot.y + size.height / 2)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }

    private var nsCursor: NSCursor {
        switch state.cursorKind {
        case .arrow: .arrow
        case .openHand: .openHand
        case .closedHand: .closedHand
        case .dragCopy: .dragCopy
        }
    }
}

private struct ClickRipple: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            .background(Circle().fill(Color.white.opacity(0.15)))
            .frame(width: 34, height: 34)
            .scaleEffect(expanded ? 1.4 : 0.3)
            .opacity(expanded ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 0.45)) { expanded = true } }
            .allowsHitTesting(false)
    }
}

/// The Touch ID prompt System Settings shows before adding to a privacy list.
struct AuthPrompt: View {
    let state: DemoState

    static let settingsIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app")

    var body: some View {
        SystemAlert(
            icon: Self.settingsIcon,
            badge: "lock.fill",
            badgeTint: .gray,
            title: "Privacy & Security",
            message: "System Settings is trying to modify your Accessibility settings.\n\nTouch ID or enter your password to allow this.",
            buttons: [AlertButton("Use Password\u{2026}"), AlertButton("Cancel")],
            withinWindow: false
        ) {
            Image(systemName: "touchid")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(state.touchAccepted ? Color.accentColor : Color(red: 1, green: 0.3, blue: 0.38))
                .scaleEffect(state.touchAccepted ? 1.1 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state.touchAccepted)
                .padding(.top, 14)
        }
        .environment(\.colorScheme, .dark)
        .padding(40) // room for the shadow
    }
}
