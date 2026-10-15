import AppKit
import SwiftUI

/// A stand-in for System Settings › Privacy & Security › Accessibility (Sequoia, dark).
struct SettingsPane: View {
    let state: DemoState

    static let size = CGSize(width: 715, height: 540)
    static let sidebarWidth: CGFloat = 215

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: Self.sidebarWidth)
            Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(white: 0.155))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "chevron.left")
                    .frame(width: 30)
                    .foregroundStyle(.white.opacity(0.75))
                Image(systemName: "chevron.right")
                    .frame(width: 30)
                    .foregroundStyle(.white.opacity(0.25))
                Text("Accessibility")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.leading, 12)
            }
            .font(.system(size: 15, weight: .medium))
            .frame(height: 52)
            .padding(.leading, 12)

            list
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Allow the applications below to control your computer.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 10)
                .frame(height: 38)
            divider(inset: 0)
            ForEach(Array(state.listApps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { divider(inset: 40) }
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                    Text(app.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    MiniSwitch(isOn: app.enabled)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            divider(inset: 0)
            HStack(spacing: 0) {
                Image(systemName: "plus").frame(width: 26)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14)
                Image(systemName: "minus").frame(width: 26)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 4)
            .frame(height: 26)
        }
        .background(shape.fill(Color.white.opacity(0.045)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        // Finder-style drop highlight while the app hovers over the list.
        .overlay {
            shape.strokeBorder(Color.accentColor, lineWidth: 2.5)
                .background(shape.fill(Color.accentColor.opacity(0.08)))
                .opacity(state.dropTargeted ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: state.dropTargeted)
        }
        .anchor("settings.list")
    }

    private func divider(inset: CGFloat) -> some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, inset).padding(.trailing, inset > 0 ? 10 : 0)
    }
}

/// The small blue switch System Settings uses in lists.
struct MiniSwitch: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.white.opacity(0.17))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color(white: isOn ? 0.97 : 0.82))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .frame(width: 13, height: 13)
                    .padding(1)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isOn)
    }
}

private struct Sidebar: View {
    struct Item: Hashable {
        let title: String
        let symbol: String
        let color: Color
    }

    static let sections: [[Item]] = [
        [
            Item(title: "Wi\u{2011}Fi", symbol: "wifi", color: .blue),
            Item(title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right", color: .blue),
            Item(title: "Network", symbol: "network", color: .blue),
            Item(title: "Battery", symbol: "battery.100percent", color: .green),
        ],
        [
            Item(title: "General", symbol: "gearshape.fill", color: .gray),
            Item(title: "Accessibility", symbol: "accessibility", color: .blue),
            Item(title: "Appearance", symbol: "circle.lefthalf.filled", color: Color(white: 0.2)),
            Item(title: "Control Center", symbol: "switch.2", color: .gray),
            Item(title: "Desktop & Dock", symbol: "menubar.dock.rectangle", color: Color(white: 0.2)),
            Item(title: "Displays", symbol: "sun.max.fill", color: .blue),
        ],
        [
            Item(title: "Notifications", symbol: "bell.badge.fill", color: .red),
            Item(title: "Sound", symbol: "speaker.wave.3.fill", color: .pink),
            Item(title: "Focus", symbol: "moon.fill", color: .indigo),
            Item(title: "Screen Time", symbol: "hourglass", color: .indigo),
        ],
        [
            Item(title: "Lock Screen", symbol: "lock.fill", color: Color(white: 0.2)),
            Item(title: "Privacy & Security", symbol: "hand.raised.fill", color: .blue),
            Item(title: "Touch ID & Password", symbol: "touchid", color: .pink),
            Item(title: "Users & Groups", symbol: "person.2.fill", color: .blue),
        ],
    ]

    var body: some View {
        ZStack(alignment: .top) {
            SidebarMaterial()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
                .padding(.horizontal, 10)

                account.padding(.top, 14)

                ForEach(Self.sections, id: \.self) { section in
                    VStack(spacing: 2) {
                        ForEach(section, id: \.self, content: row)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.top, 52)
            // Overflow runs off the bottom, as if the list scrolls.
            .frame(height: SettingsPane.size.height, alignment: .top)
        }
        .clipped()
    }

    private var account: some View {
        let name = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return HStack(spacing: 8) {
            Text(initials)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.4)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Text("Apple Account").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
    }

    private func row(_ item: Item) -> some View {
        let selected = item.title == "Privacy & Security"
        return HStack(spacing: 7) {
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(item.color.gradient))
            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background {
            if selected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor) }
        }
        .padding(.horizontal, 10)
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
