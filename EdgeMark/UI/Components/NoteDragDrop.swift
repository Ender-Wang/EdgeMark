import AppKit
import Foundation
import SwiftUI

/// Internal drag payload encoding and drop-target handling.
enum EdgeMarkDragPayload {
    nonisolated static let typeIdentifier = "io.github.ender-wang.edgemark.drag-item"
    nonisolated static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    private nonisolated struct CodablePayload: Codable {
        let kind: String
        let value: String
    }

    nonisolated static func data(for item: NoteStore.DragItem) -> Data {
        let payload = switch item {
        case let .note(id):
            CodablePayload(kind: "note", value: id.uuidString)
        case let .folder(path):
            CodablePayload(kind: "folder", value: path)
        }
        return try! JSONEncoder().encode(payload)
    }

    nonisolated static func item(from data: Data) -> NoteStore.DragItem? {
        guard let payload = try? JSONDecoder().decode(CodablePayload.self, from: data) else { return nil }
        switch payload.kind {
        case "note":
            return UUID(uuidString: payload.value).map(NoteStore.DragItem.note)
        case "folder":
            return payload.value.isEmpty ? nil : NoteStore.DragItem.folder(payload.value)
        default:
            return nil
        }
    }

    nonisolated static func item(from pasteboard: NSPasteboard) -> NoteStore.DragItem? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return item(from: data)
    }
}

struct EdgeMarkDropTargetModifier: ViewModifier {
    @Environment(NoteStore.self) private var noteStore
    let target: NoteStore.DropTarget
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                EdgeMarkDropTargetView(
                    target: target,
                    noteStore: noteStore,
                    isTargeted: $isTargeted,
                )
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(targetColor.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(targetColor, lineWidth: 2)
                        }
                        .allowsHitTesting(false)
                }
            }
    }

    private var targetColor: Color {
        switch target {
        case .folder:
            .accentColor
        case .note:
            .orange
        }
    }
}

private struct EdgeMarkDropTargetView: NSViewRepresentable {
    let target: NoteStore.DropTarget
    let noteStore: NoteStore
    @Binding var isTargeted: Bool

    func makeNSView(context _: Context) -> DragDropDestinationView {
        DragDropDestinationView()
    }

    func updateNSView(_ nsView: DragDropDestinationView, context _: Context) {
        nsView.target = target
        nsView.noteStore = noteStore
        nsView.onTargetedChanged = { targeted in
            isTargeted = targeted
        }
    }
}

private final class DragDropDestinationView: NSView {
    var target: NoteStore.DropTarget?
    var noteStore: NoteStore?
    var onTargetedChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([EdgeMarkDragPayload.pasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([EdgeMarkDragPayload.pasteboardType])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .leftMouseDragged else { return nil }
        return bounds.contains(point) ? self : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateTargeted(using: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateTargeted(using: sender)
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        onTargetedChanged?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { onTargetedChanged?(false) }
        guard let item = EdgeMarkDragPayload.item(from: sender.draggingPasteboard),
              let target,
              let noteStore,
              noteStore.canDrop(item, onto: target)
        else { return false }
        noteStore.moveDraggedItem(item, onto: target)
        return true
    }

    private func updateTargeted(using sender: any NSDraggingInfo) -> NSDragOperation {
        guard let item = EdgeMarkDragPayload.item(from: sender.draggingPasteboard),
              let target,
              let noteStore,
              noteStore.canDrop(item, onto: target)
        else {
            onTargetedChanged?(false)
            return []
        }
        onTargetedChanged?(true)
        return .move
    }
}

extension View {
    func edgeMarkDropTarget(_ target: NoteStore.DropTarget) -> some View {
        modifier(EdgeMarkDropTargetModifier(target: target))
    }
}
