import AppKit
import SwiftUI

/// Transparent overlay that turns whatever it covers into a native drag
/// source for an `.app` bundle — the same pasteboard Finder produces, which
/// is what System Settings' privacy lists accept.
struct AppDragSource: NSViewRepresentable {
    var appURL: URL
    var dragImage: NSImage
    var onHover: (Bool) -> Void
    var onPress: (Bool) -> Void
    var onDragBegan: () -> Void
    var onDragEnded: (_ dropped: Bool) -> Void

    func makeNSView(context: Context) -> AppDragSourceView { AppDragSourceView() }

    func updateNSView(_ view: AppDragSourceView, context: Context) {
        view.appURL = appURL
        view.dragImage = dragImage
        view.onHover = onHover
        view.onPress = onPress
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class AppDragSourceView: NSView, NSDraggingSource {
    var appURL: URL?
    var dragImage: NSImage?
    var onHover: (Bool) -> Void = { _ in }
    var onPress: (Bool) -> Void = { _ in }
    var onDragBegan: () -> Void = {}
    var onDragEnded: (Bool) -> Void = { _ in }

    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    // The guide panel never activates the app, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
        onPress(true)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        NSCursor.openHand.set()
        onPress(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownPoint, let appURL else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }

        let item = NSPasteboardItem()
        item.setString(appURL.absoluteString, forType: .fileURL)
        item.setPropertyList([appURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let image = dragImage ?? NSWorkspace.shared.icon(forFile: appURL.path)
        let size = image.size
        draggingItem.setDraggingFrame(
            NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
            contents: image
        )

        isDragging = true
        onPress(false)
        onDragBegan()
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        mouseDownPoint = nil
        onDragEnded(operation != [])
    }
}
