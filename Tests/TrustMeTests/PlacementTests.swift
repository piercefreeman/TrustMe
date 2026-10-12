import CoreGraphics
import Testing
@testable import TrustMe

@Suite("Guide placement")
struct PlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let panel = CGSize(width: 380, height: 86)

    @Test("Docks below the list pane when there's room")
    func below() {
        let settings = CGRect(x: 300, y: 400, width: 715, height: 480)
        let (origin, edge) = GuidePlacement.place(panelSize: panel, beside: settings, within: screen)
        #expect(edge == .below)
        #expect(origin.y == settings.minY - GuidePlacement.gap - panel.height)
        // Centred under the content pane, right of the ~32% sidebar.
        let sidebar = min(260, settings.width * 0.32)
        let contentMidX = settings.minX + sidebar + (settings.width - sidebar) / 2
        #expect(abs(origin.x + panel.width / 2 - contentMidX) < 0.5)
    }

    @Test("Moves to the right when Settings fills the bottom of the screen")
    func right() {
        let settings = CGRect(x: 100, y: 20, width: 715, height: 860)
        let (origin, edge) = GuidePlacement.place(panelSize: panel, beside: settings, within: screen)
        #expect(edge == .right)
        #expect(origin.x == settings.maxX + GuidePlacement.gap)
    }

    @Test("Moves to the left when there's no room below or right")
    func left() {
        let settings = CGRect(x: 700, y: 20, width: 715, height: 860)
        let (origin, edge) = GuidePlacement.place(panelSize: panel, beside: settings, within: screen)
        #expect(edge == .left)
        #expect(origin.x == settings.minX - GuidePlacement.gap - panel.width)
    }

    @Test("Overlays the window when it fills the screen")
    func inside() {
        let (origin, edge) = GuidePlacement.place(panelSize: panel, beside: screen, within: screen)
        #expect(edge == .inside)
        #expect(screen.contains(CGRect(origin: origin, size: panel)))
    }

    @Test("Never leaves the visible screen area", arguments: [
        CGRect(x: -200, y: 300, width: 715, height: 480),
        CGRect(x: 1100, y: 300, width: 715, height: 480),
    ])
    func clamped(settings: CGRect) {
        let (origin, _) = GuidePlacement.place(panelSize: panel, beside: settings, within: screen)
        #expect(screen.contains(CGRect(origin: origin, size: panel)))
    }

    @Test("Window Server rects flip to Cocoa coordinates")
    @MainActor
    func coordinateFlip() {
        let rect = SystemSettingsWindow.cocoaRect(fromWindowServer: CGRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 900)
        #expect(rect == CGRect(x: 10, y: 830, width: 100, height: 50))
    }

    @Test("Direction copy follows the edge")
    func directions() {
        #expect(GuideEdge.below.direction == "above")
        #expect(GuideEdge.inside.direction == "above")
        #expect(GuideEdge.right.direction == "to the left")
        #expect(GuideEdge.left.direction == "to the right")
    }
}
