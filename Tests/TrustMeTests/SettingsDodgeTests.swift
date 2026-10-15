import CoreGraphics
import Testing
@testable import TrustMe

@Suite("Settings dodge")
struct SettingsDodgeTests {
    let size = CGSize(width: 920, height: 600)
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 900)
    let centered = CGRect(x: 296, y: 150, width: 920, height: 600)

    @Test("Moves beside Settings, flush against it, without covering it")
    func beside() {
        let settings = CGRect(x: 700, y: 100, width: 715, height: 650)
        let placed = SettingsDodge.place(size, besides: settings, within: laptop, from: centered)
        #expect(!placed.intersects(settings))
        #expect(placed.maxX == settings.minX - 16)
        #expect(placed.minY == centered.minY, "Only moves sideways")
    }

    @Test("Goes to the side with more room")
    func moreRoom() {
        let settings = CGRect(x: 0, y: 100, width: 715, height: 650)
        let placed = SettingsDodge.place(size, besides: settings, within: laptop, from: centered)
        #expect(placed.minX == settings.maxX + 16)
        #expect(!placed.intersects(settings))
    }

    @Test("Stays fully on screen when there's room")
    func onScreen() {
        let wide = CGRect(x: 0, y: 0, width: 3000, height: 1200)
        let settings = CGRect(x: 1100, y: 300, width: 715, height: 650)
        let placed = SettingsDodge.place(size, besides: settings, within: wide, from: CGRect(origin: CGPoint(x: 1000, y: 300), size: size))
        #expect(wide.contains(placed))
        #expect(!placed.intersects(settings))
    }

    @Test("Keeps enough on screen to click it back when Settings fills the screen")
    func hangsOff() {
        let placed = SettingsDodge.place(size, besides: laptop.insetBy(dx: 10, dy: 10), within: laptop, from: centered)
        #expect(placed.intersection(laptop).width == 240)
    }

    @Test("Clamps its height into the visible area")
    func clamps() {
        let settings = CGRect(x: 700, y: 100, width: 715, height: 650)
        let high = CGRect(origin: CGPoint(x: 296, y: 800), size: size)
        #expect(SettingsDodge.place(size, besides: settings, within: laptop, from: high).maxY == laptop.maxY)
    }

    // MARK: Is Settings under the window?

    func entry(_ number: Int, pid: pid_t, layer: Int = 0, bounds: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: bounds.dictionaryRepresentation]
    }

    @Test("Settings listed after the window is behind it, in Cocoa coordinates")
    func behind() {
        let list = [entry(7, pid: 1, layer: 3, bounds: centered), entry(9, pid: 42, bounds: CGRect(x: 100, y: 50, width: 715, height: 650))]
        let found = SettingsDodge.frontmostSettings(in: list, pids: [42], above: 7, primaryHeight: 900)
        #expect(found?.isBehind == true)
        #expect(found?.frame == CGRect(x: 100, y: 200, width: 715, height: 650))
    }

    @Test("Settings listed before the window is in front of it")
    func inFront() {
        let list = [entry(9, pid: 42, bounds: CGRect(x: 100, y: 50, width: 715, height: 650)), entry(7, pid: 1, bounds: centered)]
        #expect(SettingsDodge.frontmostSettings(in: list, pids: [42], above: 7, primaryHeight: 900)?.isBehind == false)
    }

    @Test("Skips Settings' sheets and small windows")
    func skips() {
        let list = [entry(7, pid: 1, layer: 3, bounds: centered),
                    entry(8, pid: 42, layer: 8, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
                    entry(9, pid: 42, bounds: CGRect(x: 0, y: 0, width: 200, height: 100)),
                    entry(10, pid: 42, bounds: CGRect(x: 100, y: 50, width: 715, height: 650))]
        #expect(SettingsDodge.frontmostSettings(in: list, pids: [42], above: 7, primaryHeight: 900)?.frame.width == 715)
    }

    @Test("No Settings window")
    func none() {
        #expect(SettingsDodge.frontmostSettings(in: [entry(7, pid: 1, bounds: centered)], pids: [42], above: 7, primaryHeight: 900) == nil)
    }
}
