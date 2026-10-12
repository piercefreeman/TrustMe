// Renders every guide-panel state over several backdrops (the desktop
// wallpaper, a dark and a bright surface) beneath a real System Settings
// capture, and saves a screenshot for design review.
//
//   swift run TrustMeRender --settings settings.png --app build/TrustMe.app --out render.png
import AppKit
import SwiftUI
@testable import TrustMe

let args = ProcessInfo.processInfo.arguments
func arg(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
}

let columnWidth: CGFloat = 430
let headerHeight: CGFloat = 36
let settingsStrip: CGFloat = 200
let rowHeight: CGFloat = 104

struct Row { let label: String; let phase: GuideModel.Phase; let hover: Bool }
let rows = [
    Row(label: "waiting", phase: .waiting, hover: false),
    Row(label: "hover", phase: .waiting, hover: true),
    Row(label: "dropped", phase: .dropped, hover: false),
    Row(label: "stalled", phase: .stalled, hover: true),
    Row(label: "granted", phase: .granted, hover: false),
]
enum Surface: String, CaseIterable { case wallpaper, dark, bright }
let surfaces = Surface.allCases

struct Backdrop: View {
    let settings: NSImage?
    let wallpaper: NSImage?

    var body: some View {
            HStack(spacing: 0) {
                ForEach(surfaces, id: \.self) { surface in
                    VStack(spacing: 0) {
                        Text(surface.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(height: headerHeight)
                        // Bottom of the Settings window, centred on its list pane.
                        Color.clear
                            .frame(width: columnWidth, height: settingsStrip)
                            .overlay(alignment: .bottom) {
                                if let settings {
                                    Image(nsImage: settings)
                                        .fixedSize()
                                        .offset(x: -settings.size.width * 0.16)
                                }
                            }
                            .clipped()
                        ForEach(rows, id: \.label) { row in
                            Text(row.label)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)
                                .padding(.leading, 8)
                        }
                    }
                    .frame(width: columnWidth)
                    // In a background so the aspect-filled wallpaper can't inflate the layout.
                    .background { background(for: surface) }
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func background(for surface: Surface) -> some View {
        switch surface {
        case .wallpaper:
            if let wallpaper {
                Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.indigo, .purple, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .dark: Color(white: 0.12)
        case .bright: LinearGradient(colors: [Color(white: 0.96), Color(red: 0.85, green: 0.9, blue: 1)], startPoint: .top, endPoint: .bottom)
        }
    }
}

@MainActor
final class Renderer: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = arg("--settings").flatMap { NSImage(contentsOfFile: $0) }
        if let settings, let rep = settings.representations.first {
            settings.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
        }
        let screen = NSScreen.main!
        let wallpaper = NSWorkspace.shared.desktopImageURL(for: screen).flatMap { NSImage(contentsOf: $0) }

        let appURL = URL(fileURLWithPath: arg("--app") ?? "build/TrustMe.app")
        let app = AppIdentity(url: appURL, name: "TrustMe", icon: NSWorkspace.shared.icon(forFile: appURL.path))

        let size = CGSize(
            width: columnWidth * CGFloat(surfaces.count),
            height: headerHeight + settingsStrip + rowHeight * CGFloat(rows.count)
        )
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.minX + 20, y: visible.maxY - size.height - 20, width: size.width, height: size.height)

        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.contentView = NSHostingView(rootView: Backdrop(settings: settings, wallpaper: wallpaper))
        backdrop.orderFrontRegardless()
        windows.append(backdrop)

        for column in surfaces.indices {
            for (index, row) in rows.enumerated() {
                let model = GuideModel(permission: .accessibility, app: app)
                model.phase = row.phase
                model.showsClose = row.hover
                model.isHovering = row.hover
                model.isStill = true
                model.isPresented = true
                model.edge = .below

                let hosting = NSHostingView(rootView: DragGuideView(model: model))
                hosting.layoutSubtreeIfNeeded()
                let panelSize = hosting.fittingSize
                let panel = GuidePanel(contentRect: CGRect(origin: .zero, size: panelSize))
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                panel.contentView = hosting
                let slotTop = frame.maxY - headerHeight - settingsStrip - rowHeight * CGFloat(index)
                panel.setFrameOrigin(CGPoint(
                    x: frame.minX + columnWidth * CGFloat(column) + (columnWidth - panelSize.width) / 2,
                    y: slotTop - 12 - panelSize.height
                ))
                panel.orderFrontRegardless()
                windows.append(panel)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let primaryHeight = NSScreen.screens[0].frame.height
            let rect = "\(Int(frame.minX)),\(Int(primaryHeight - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-R", rect, arg("--out") ?? "render.png"]
            try? capture.run()
            capture.waitUntilExit()
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let renderer = Renderer()
app.delegate = renderer
app.run()
