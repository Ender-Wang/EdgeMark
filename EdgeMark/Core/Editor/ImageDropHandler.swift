import AppKit
import SwiftUI

// MARK: - Drop target view

final class DropTargetView: NSView {
    var onImageURLDropped: ((URL) -> Void)?

    private static let imageTypes: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "tiff", "tif", "bmp", "heic", "heif"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Transparent to all mouse/key events — only drag-and-drop lands here.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasImageFile(in: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasImageFile(in: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: ["public.image"],
        ]) as? [URL],
            let url = urls.first
        else { return false }
        // Defer to next run loop so the drag session finishes and the window
        // restores first-responder state before we look for the text view.
        DispatchQueue.main.async { [weak self] in
            self?.onImageURLDropped?(url)
        }
        return true
    }

    private func hasImageFile(in pasteboard: NSPasteboard) -> Bool {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: ["public.image"],
        ]) as? [URL] else { return false }
        return urls.contains { Self.imageTypes.contains($0.pathExtension.lowercased()) }
    }
}

// MARK: - SwiftUI wrapper

struct ImageDropOverlay: NSViewRepresentable {
    let onImageURLDropped: (URL) -> Void

    func makeNSView(context _: Context) -> DropTargetView {
        let v = DropTargetView()
        v.onImageURLDropped = onImageURLDropped
        return v
    }

    func updateNSView(_ nsView: DropTargetView, context _: Context) {
        nsView.onImageURLDropped = onImageURLDropped
    }
}

// MARK: - Helpers

/// Walk the view hierarchy from `root` and return the first NSTextView found
/// inside an NSScrollView (NativeTextViewWrapper's structure).
func findEditorTextView(in root: NSView?) -> NSTextView? {
    guard let root else { return nil }
    if let scroll = root as? NSScrollView, let tv = scroll.documentView as? NSTextView {
        return tv
    }
    for sub in root.subviews {
        if let found = findEditorTextView(in: sub) {
            return found
        }
    }
    return nil
}
