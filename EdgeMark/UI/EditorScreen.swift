import Cocoa
import SwiftUI

struct EditorScreen: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @Environment(L10n.self) var l10n
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false
    @State private var editorCoordinator: MarkdownEditorView.Coordinator?

    private var backLabel: String {
        noteStore.selectedFolder?.name ?? l10n["common.home"]
    }

    var body: some View {
        PageLayout(
            onSwipeBack: { goBack() },
            onContentSwipeRight: ShortcutSettings.shared.editorSwipeToNavigateEnabled
                ? { noteStore.navigateToPreviousNote(sortedBy: appSettings) } : nil,
            onContentSwipeLeft: ShortcutSettings.shared.editorSwipeToNavigateEnabled
                ? { noteStore.navigateToNextNote(sortedBy: appSettings) } : nil,
        ) {
            headerContent
        } content: {
            if let note = noteStore.selectedNote {
                MarkdownEditorView(
                    noteID: note.id,
                    initialContent: note.content,
                    colorScheme: colorScheme,
                    onContentChanged: { newContent in
                        noteStore.updateContent(for: note.id, content: newContent)
                    },
                    onCoordinatorReady: { coordinator in
                        editorCoordinator = coordinator
                    },
                    onNavigateNext: { noteStore.navigateToNextNote(sortedBy: appSettings) },
                    onNavigatePrevious: { noteStore.navigateToPreviousNote(sortedBy: appSettings) },
                )
            }
        }
        .alert(l10n["alert.deleteNote.title"], isPresented: $showDeleteConfirm) {
            Button(l10n["common.delete"], role: .destructive) {
                if let note = noteStore.selectedNote {
                    noteStore.closeNote()
                    noteStore.deleteNote(note)
                }
            }
            Button(l10n["common.cancel"], role: .cancel) {}
        }
    }

    @ViewBuilder
    private var headerContent: some View {
        if let note = noteStore.selectedNote {
            VStack(spacing: 4) {
                HStack {
                    HeaderIconButton(
                        systemName: "chevron.left",
                        help: backLabel,
                    ) {
                        goBack()
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(note.title.isEmpty ? l10n["common.untitled"] : note.title)
                            .font(.headline)
                            .lineLimit(1)

                        Text(note.displayDirectory)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    CopyMenuButton(note: note, coordinator: editorCoordinator)

                    DeleteIconButton {
                        showDeleteConfirm = true
                    }
                }

                HStack(spacing: 12) {
                    DateLabelView(
                        systemName: "clock",
                        date: note.modifiedAt.homeDisplayFormat,
                        tooltip: L10n.shared.t("editor.modifiedAt", note.modifiedAt.homeDisplayFormat),
                    )

                    DateLabelView(
                        systemName: "calendar",
                        date: note.createdAt.homeDisplayFormat,
                        tooltip: L10n.shared.t("editor.createdAt", note.createdAt.homeDisplayFormat),
                    )
                }
            }
        }
    }

    private func goBack() {
        noteStore.closeNote()
    }
}

// MARK: - Copy Menu Button

/// Copy icon that opens a menu with plain text and Markdown copy options.
/// If text is selected in the editor, copies the selection; otherwise copies the whole document.
private struct CopyMenuButton: View {
    let note: Note
    let coordinator: MarkdownEditorView.Coordinator?

    @State private var isHovered = false

    var body: some View {
        let l10n = L10n.shared
        Menu {
            Button(l10n["common.copyPlainText"]) {
                Task {
                    let selected = await coordinator?.getSelectedText() ?? ""
                    let source = selected.isEmpty ? note.content : selected
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Note.plainText(from: source), forType: .string)
                }
            }
            Button(l10n["common.copyMarkdown"]) {
                Task {
                    let selected = await coordinator?.getSelectedText() ?? ""
                    let text = selected.isEmpty ? note.content : selected
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            Button(l10n["common.copyRTF"]) {
                Task {
                    let selected = await coordinator?.getSelectedText() ?? ""
                    let source = selected.isEmpty ? note.content : selected
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    if let rtf = Note.rtfData(from: source) {
                        pb.setData(rtf, forType: .rtf)
                    } else {
                        pb.setString(Note.plainText(from: source), forType: .string)
                    }
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(isHovered ? 0.1 : 0))
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n["editor.copyNote"])
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Delete Icon Button

/// Trash icon that turns red on hover.
private struct DeleteIconButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHovered ? .red : .secondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(isHovered ? 0.1 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.shared["editor.deleteNote"])
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Date Label View

/// Icon + date text in a compact row with hover tooltip.
private struct DateLabelView: View {
    let systemName: String
    let date: String
    let tooltip: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
            Text(date)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .contentShape(Rectangle())
        .help(tooltip)
    }
}
