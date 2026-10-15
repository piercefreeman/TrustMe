import AppKit
import SwiftUI

/// The fake desktop: wallpaper plus a menu bar.
public struct DesktopBackdrop: View {
    let wallpaper: NSImage?
    let showsMenuBar: Bool

    public init(wallpaper: NSImage?, showsMenuBar: Bool = true) {
        self.wallpaper = wallpaper
        self.showsMenuBar = showsMenuBar
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .background {
                    if let wallpaper {
                        Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [.indigo, .purple, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .clipped()
            if showsMenuBar { MenuBar() }
        }
        .ignoresSafeArea()
    }
}

/// A static stand-in for the macOS menu bar.
public struct MenuBar: View {
    public init() {}

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d  h:mm a"
        return formatter
    }()

    public var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 15))
                Text(Demo.appName).fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0) }
            }
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "battery.75percent")
                Image(systemName: "wifi")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.clock.string(from: context.date))
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        .padding(.horizontal, 18)
        .frame(height: Demo.menuBarHeight)
        .background(Color.black.opacity(0.14))
    }
}
