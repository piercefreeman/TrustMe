// A full-screen simulation of macOS permission popups piling up: the first
// one alone in the center, then faster and faster until the desktop is buried.
//
//   swift run PopupStorm            Esc quits, R replays
import AppKit
import DemoSupport
import Observation
import SwiftUI

// MARK: - The prompts

struct PromptKind {
    let badge: String
    let tint: Color
    let title: String
    let message: String?
    let buttons: [AlertButton]
    var keychain = false
}

let app = "\u{201C}\(Demo.appName)\u{201D}"
let inSettings = "Grant access to this application in Privacy & Security settings, located in System Settings."
let openOrDeny = [AlertButton("Open System Settings", isDefault: true), AlertButton("Deny")]
let denyOrAllow = [AlertButton("Don\u{2019}t Allow"), AlertButton("Allow", isDefault: true)]

let accessibilityPrompt = PromptKind(
    badge: "accessibility", tint: .blue,
    title: "\(app) would like to control this computer using accessibility features.",
    message: inSettings, buttons: openOrDeny
)

let prompts: [PromptKind] = [
    PromptKind(badge: "rectangle.dashed.badge.record", tint: .red,
               title: "\(app) would like to record this computer\u{2019}s screen and audio.",
               message: inSettings, buttons: openOrDeny),
    PromptKind(badge: "keyboard.fill", tint: .purple,
               title: "\(app) would like to receive keystrokes from any application.",
               message: inSettings, buttons: openOrDeny),
    PromptKind(badge: "folder.fill", tint: .blue,
               title: "\(app) would like to access files in your Documents folder.",
               message: nil, buttons: denyOrAllow),
    PromptKind(badge: "menubar.dock.rectangle", tint: .teal,
               title: "\(app) would like to access files in your Desktop folder.",
               message: nil, buttons: denyOrAllow),
    PromptKind(badge: "arrow.down.circle.fill", tint: .blue,
               title: "\(app) would like to access files in your Downloads folder.",
               message: nil, buttons: denyOrAllow),
    PromptKind(badge: "camera.fill", tint: .green,
               title: "\(app) would like to access the camera.",
               message: "\(Demo.appName) uses the camera for video calls.", buttons: denyOrAllow),
    PromptKind(badge: "mic.fill", tint: .orange,
               title: "\(app) would like to access the microphone.",
               message: "\(Demo.appName) uses the microphone for dictation.", buttons: denyOrAllow),
    PromptKind(badge: "gearshape.2.fill", tint: .gray,
               title: "\(app) wants access to control \u{201C}System Events\u{201D}. Allowing control will provide access to documents and data in \u{201C}System Events\u{201D}, and to perform actions within that app.",
               message: "\(Demo.appName) automates other apps for you.", buttons: denyOrAllow),
    PromptKind(badge: "person.crop.circle.fill", tint: .brown,
               title: "\(app) would like to access your contacts.",
               message: nil, buttons: denyOrAllow),
    PromptKind(badge: "calendar", tint: .red,
               title: "\(app) would like full access to your Calendar.",
               message: "\(Demo.appName) needs your calendar to schedule meetings.",
               buttons: [AlertButton("Don\u{2019}t Allow"), AlertButton("Allow Full Access", isDefault: true)]),
    PromptKind(badge: "location.fill", tint: .blue,
               title: "Allow \(app) to use your current location?",
               message: "Your location is used to show nearby results.",
               buttons: [AlertButton("Allow Once"), AlertButton("Allow While Using App", isDefault: true), AlertButton("Don\u{2019}t Allow")]),
    PromptKind(badge: "network", tint: .blue,
               title: "Allow \(app) to find devices on local networks?",
               message: "This will allow the app to discover, connect to, and collect data from devices on your networks.",
               buttons: denyOrAllow),
    PromptKind(badge: "antenna.radiowaves.left.and.right", tint: .blue,
               title: "\(app) would like to use Bluetooth.",
               message: "\(Demo.appName) connects to nearby accessories.",
               buttons: [AlertButton("Don\u{2019}t Allow"), AlertButton("OK", isDefault: true)]),
    PromptKind(badge: "photo.fill", tint: .pink,
               title: "\(app) would like to access your Photos.",
               message: nil, buttons: denyOrAllow),
    PromptKind(badge: "externaldrive.fill", tint: .gray,
               title: "\(app) would like to access files on a removable volume.",
               message: nil, buttons: denyOrAllow),
    PromptKind(badge: "key.fill", tint: .gray,
               title: "\(Demo.appName) wants to use your confidential information stored in \u{201C}\(Demo.appName) Safe Storage\u{201D} in your keychain.",
               message: "To allow this, enter the \u{201C}login\u{201D} keychain password.",
               buttons: [AlertButton("Allow", isDefault: true), AlertButton("Always Allow"), AlertButton("Deny")],
               keychain: true),
    PromptKind(badge: "checklist", tint: .orange,
               title: "\(app) would like to access your reminders.",
               message: nil, buttons: denyOrAllow),
]

struct Prompt: View {
    let kind: PromptKind
    let icon: NSImage

    var body: some View {
        SystemAlert(icon: icon, badge: kind.badge, badgeTint: kind.tint, title: kind.title, message: kind.message, buttons: kind.buttons) {
            if kind.keychain {
                Text("Password")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2.5).padding(-2))
                    .padding(.top, 12)
            }
        }
    }
}

// MARK: - The storm

@MainActor
@Observable
final class Storm {
    struct Popup: Identifiable {
        let id: Int
        let kind: PromptKind
        let center: CGPoint
    }

    var popups: [Popup] = []

    @ObservationIgnored let area: CGRect
    @ObservationIgnored let sizes: [CGSize]
    @ObservationIgnored let accessibilitySize: CGSize
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deck: [Int] = []

    // Coverage grid, so placement keeps finding the bare spots until none are left.
    @ObservationIgnored private let cell: CGFloat = 12
    @ObservationIgnored private var covered: [[Bool]] = []

    init(area: CGRect, icon: NSImage) {
        self.area = area
        func measure(_ kind: PromptKind) -> CGSize {
            let hosting = NSHostingView(rootView: Prompt(kind: kind, icon: icon))
            return hosting.fittingSize
        }
        sizes = prompts.map(measure)
        accessibilitySize = measure(accessibilityPrompt)
    }

    func start() {
        task?.cancel()
        popups = []
        deck = []
        covered = Array(repeating: Array(repeating: false, count: Int(ceil(area.width / cell))), count: Int(ceil(area.height / cell)))

        task = Task { @MainActor [weak self] in
            // A beat of plain desktop first (`--hold <seconds>` to change it).
            try? await Task.sleep(for: .seconds(Demo.arg("--hold").flatMap(Double.init) ?? 3.5))
            guard let self, !Task.isCancelled else { return }
            self.add(accessibilityPrompt, size: self.accessibilitySize, at: CGPoint(x: self.area.midX, y: self.area.midY))

            var extra = 0
            for n in 0..<400 {
                // Long pauses at first, then a quickening flood.
                let interval = max(0.03, 2.2 * pow(0.8, Double(n)))
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }

                let index = self.nextKind()
                let size = self.sizes[index]
                let (point, gain) = self.bestSpot(for: size)
                self.add(prompts[index], size: size, at: point)
                if gain == 0 { extra += 1 }
                if extra > 40 { return }
            }
        }
    }

    private func nextKind() -> Int {
        if deck.isEmpty { deck = Array(prompts.indices).shuffled() }
        return deck.removeLast()
    }

    private func add(_ kind: PromptKind, size: CGSize, at center: CGPoint) {
        mark(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
        withAnimation(.easeOut(duration: 0.2)) {
            popups.append(Popup(id: popups.count, kind: kind, center: center))
        }
    }

    /// Best of a handful of random spots, scored by how much bare desktop it covers.
    private func bestSpot(for size: CGSize) -> (CGPoint, Int) {
        let overhang: CGFloat = 40
        var best = (CGPoint(x: area.midX, y: area.midY), -1)
        for _ in 0..<24 {
            let point = CGPoint(
                x: CGFloat.random(in: (area.minX + size.width / 2 - overhang)...(area.maxX - size.width / 2 + overhang)),
                y: CGFloat.random(in: (area.minY + size.height / 2 - overhang / 2)...(area.maxY - size.height / 2 + overhang))
            )
            let gain = uncovered(in: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height))
            if gain > best.1 { best = (point, gain) }
        }
        return best
    }

    private func cells(in rect: CGRect) -> (ClosedRange<Int>, ClosedRange<Int>)? {
        let r = rect.intersection(area)
        guard !r.isNull, r.width > 0, r.height > 0 else { return nil }
        let rows = covered.count, cols = covered.first?.count ?? 0
        let x0 = max(0, Int((r.minX - area.minX) / cell)), x1 = min(cols - 1, Int((r.maxX - area.minX) / cell))
        let y0 = max(0, Int((r.minY - area.minY) / cell)), y1 = min(rows - 1, Int((r.maxY - area.minY) / cell))
        guard x0 <= x1, y0 <= y1 else { return nil }
        return (x0...x1, y0...y1)
    }

    private func uncovered(in rect: CGRect) -> Int {
        guard let (xs, ys) = cells(in: rect) else { return 0 }
        var count = 0
        for y in ys { for x in xs where !covered[y][x] { count += 1 } }
        return count
    }

    private func mark(_ rect: CGRect) {
        // Shrink a little: rounded corners and shadows don't really cover.
        guard let (xs, ys) = cells(in: rect.insetBy(dx: 8, dy: 8)) else { return }
        for y in ys { for x in xs { covered[y][x] = true } }
    }
}

struct StormView: View {
    let storm: Storm
    let wallpaper: NSImage?
    let icon: NSImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            DesktopBackdrop(wallpaper: wallpaper, showsMenuBar: false)
            ForEach(storm.popups) { popup in
                Prompt(kind: popup.kind, icon: icon)
                    .position(popup.center)
                    .transition(.asymmetric(insertion: .scale(scale: 1.08).combined(with: .opacity), removal: .identity))
            }
            // System alerts slide under the menu bar.
            MenuBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

// MARK: - Launch

Demo.run {
    let screen = Demo.screen
    let wallpaper = Wallpaper.load(for: screen)
    let icon = Demo.appIcon
    let area = CGRect(x: 0, y: Demo.menuBarHeight, width: screen.frame.width, height: screen.frame.height - Demo.menuBarHeight)
    let storm = Storm(area: area, icon: icon)

    let window = DemoWindow(frame: screen.frame, level: Demo.level(0))
    window.contentView = NSHostingView(rootView: StormView(storm: storm, wallpaper: wallpaper, icon: icon))
    window.alphaValue = 0
    window.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { $0.duration = 0.35; window.animator().alphaValue = 1 }
    NSCursor.setHiddenUntilMouseMoves(true)

    Demo.installKeys { storm.start() }
    storm.start()
}
