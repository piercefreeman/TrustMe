import AppKit
import SwiftUI
import Testing
@testable import TrustMe

@Suite("Views")
@MainActor
struct ViewTests {
    let app = AppIdentity(url: URL(fileURLWithPath: "/Applications/TrustMe.app"), name: "TrustMe",
                          icon: NSImage(systemSymbolName: "shield", accessibilityDescription: nil)!)

    @Test("Band captions for every phase", arguments: [
        (GuideModel.Phase.waiting, GuideEdge.below, "Drag into the list above to allow"),
        (.dragging, .right, "Drag into the list to the left to allow"),
        (.dropped, .below, "Approve with Touch ID or your password"),
        (.needsRelaunch, .below, "Allowed. Relaunch to apply it."),
        (.granted, .below, "Accessibility allowed"),
    ])
    func captions(phase: GuideModel.Phase, edge: GuideEdge, expected: String) {
        let model = GuideModel(permission: .accessibility, app: app)
        model.phase = phase
        model.edge = edge
        #expect(model.caption == expected)
    }

    @Test("The stalled caption names the minus button")
    func stalledCaption() {
        let model = GuideModel(permission: .accessibility, app: app)
        model.phase = .stalled
        #expect(model.caption.contains("\u{2212}"))
    }

    @Test("The band keeps its size in every phase", arguments: [
        GuideModel.Phase.waiting, .dragging, .dropped, .stalled, .needsRelaunch, .granted,
    ])
    func bandSize(phase: GuideModel.Phase) {
        let model = GuideModel(permission: .accessibility, app: app)
        model.phase = phase
        model.isPresented = true
        let view = NSHostingView(rootView: DragGuideView(model: model))
        let size = view.fittingSize
        #expect(size.width == DragGuideView.width + DragGuideView.inset * 2)
        #expect(size.height >= 66 + DragGuideView.inset * 2)
    }

    @Test("The drag image renders")
    func dragImage() {
        let image = DragChip.render(app: app)
        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
    }

    @Test("The permissions screen lays out for any list", arguments: [1, 3, 6])
    func permissionsView(count: Int) {
        let permissions = Array(Permission.allDraggable.prefix(count))
        let view = NSHostingView(rootView: PermissionsView(permissions, onContinue: {}))
        let size = view.fittingSize
        #expect(size.width == 620)
        #expect(size.height > 300)
    }

    @Test("Rows and buttons render on their own")
    func components() {
        let row = NSHostingView(rootView: PermissionRow(.accessibility, detail: "Custom copy").frame(width: 500))
        #expect(row.fittingSize.height > 40)
        let button = NSHostingView(rootView: PermissionButton(.accessibility))
        #expect(button.fittingSize.width > 0)
    }
}
