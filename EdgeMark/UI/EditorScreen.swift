import Cocoa
import SwiftUI

struct EditorScreen: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @Environment(L10n.self) var l10n
    @State private var showDeleteConfirm = false
    @State private var pendingEditorReload: String? = nil
    @State private var isFindBarShowing = false
    @State private var noteRename = NoteRenameCoordinator()
    @FocusState private var isNoteTitleFocused: Bool

    private var backLabel: String {
        noteStore.selectedFolder?.name ?? l10n["common.home"]
    }

    var body: some View {
        PageLayout(
            onSwipeBack: { goBack() },
            onContentSwipeRight: PanelSettings.shared.editorSwipeToNavigateEnabled
                ? { noteStore.navigateToPreviousNote(sortedBy: appSettings) } : nil,
            onContentSwipeLeft: PanelSettings.shared.editorSwipeToNavigateEnabled
                ? { noteStore.navigateToNextNote(sortedBy: appSettings) } : nil,
        ) {
            headerContent
        } content: {
            if let note = noteStore.selectedNote {
                MarkdownEditorView(
                    noteID: note.id,
                    noteTitle: note.title,
                    noteFolder: note.folder,
                    initialContent: note.content,
                    onContentChanged: { id, newContent in
                        noteStore.updateContent(for: id, content: newContent)
                    },
                    pendingReload: $pendingEditorReload,
                    showFindBar: $isFindBarShowing,
                    onNavigateNext: { noteStore.navigateToNextNote(sortedBy: appSettings) },
                    onNavigatePrevious: { noteStore.navigateToPreviousNote(sortedBy: appSettings) },
                )
                .onAppear {
                    noteStore.onNeedEditorReload = { content in
                        pendingEditorReload = content
                    }
                }
                .onChange(of: noteStore.pendingEditorFind) { _, pending in
                    guard pending else { return }
                    noteStore.pendingEditorFind = false
                    isFindBarShowing = true
                }
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
        .alert(
            l10n["alert.externalChange.title"],
            isPresented: Binding(
                get: { noteStore.pendingExternalChange != nil },
                set: {
                    if !$0 {
                        noteStore.pendingExternalChange = nil
                    }
                },
            ),
        ) {
            Button(l10n["alert.externalChange.keepEdgeMarkEdits"]) {
                noteStore.resolveExternalChange(keepEdgeMarkEdits: true)
            }
            Button(l10n["alert.externalChange.reloadFromDisk"], role: .destructive) {
                noteStore.resolveExternalChange(keepEdgeMarkEdits: false)
            }
        } message: {
            Text(l10n["alert.externalChange.message"])
        }
    }

    @ViewBuilder
    private var headerContent: some View {
        if let note = noteStore.selectedNote {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    HeaderIconButton(
                        systemName: "chevron.left",
                        help: backLabel,
                    ) {
                        goBack()
                    }

                    NoteHeaderTitle(
                        title: note.title.isEmpty ? l10n["common.untitled"] : note.title,
                        path: note.displayPath,
                        modifiedAt: note.modifiedAt.homeDisplayFormat,
                        createdAt: note.createdAt.homeDisplayFormat,
                        text: Binding(
                            get: {
                                noteRename.renamingNoteID == note.id
                                    ? noteRename.text
                                    : note.title
                            },
                            set: { newValue in
                                if noteRename.renamingNoteID != note.id {
                                    noteRename.beginRename(note)
                                }
                                noteRename.text = newValue
                            },
                        ),
                        isFocused: $isNoteTitleFocused,
                        isEditing: noteRename.renamingNoteID == note.id,
                        isConflicting: noteRename.isConflicting(in: noteStore),
                        onBeginEditing: {
                            if noteRename.renamingNoteID != note.id {
                                noteRename.beginRename(note)
                            }
                        },
                        onCommit: {
                            noteRename.commit(note: note, noteStore: noteStore)
                            if noteRename.renamingNoteID == nil {
                                isNoteTitleFocused = false
                            }
                        },
                        onCancel: {
                            noteRename.cancel(noteStore: noteStore)
                            isNoteTitleFocused = false
                        },
                        onFocusLost: {
                            noteRename.commitOrCancel(note: note, noteStore: noteStore)
                        },
                    )

                    HStack(spacing: SurfaceMetrics.controlGroupSpacing) {
                        PinButton()

                        HeaderActionMenu(help: l10n["common.moreActions"]) { dismiss in
                            EditorActionMenuContent(
                                note: note,
                                dismiss: dismiss,
                                onDelete: { showDeleteConfirm = true },
                            )
                        }
                    }
                    .fixedSize()
                }

                if appSettings.showNoteDatesInHeader {
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
    }

    private func goBack() {
        noteStore.closeNote()
    }
}

// MARK: - Editor Action Menu

/// Editor overflow actions. If text is selected, copy actions use the selection;
/// otherwise they use the whole document.
private struct EditorActionMenuContent: View {
    let note: Note
    let dismiss: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let l10n = L10n.shared
        VStack(spacing: 2) {
            HeaderActionButton(
                title: l10n["common.copyPlainText"],
                systemName: "doc.on.doc",
            ) {
                dismiss()
                let selected = Self.getSelectedText()
                let source = selected.isEmpty ? note.content : selected
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Note.plainText(from: source), forType: .string)
            }
            HeaderActionButton(
                title: l10n["common.copyMarkdown"],
                systemName: "doc.text",
            ) {
                dismiss()
                let selected = Self.getSelectedText()
                let text = selected.isEmpty ? note.content : selected
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            HeaderActionButton(
                title: l10n["common.copyRTF"],
                systemName: "doc.richtext",
            ) {
                dismiss()
                let selected = Self.getSelectedText()
                let source = selected.isEmpty ? note.content : selected
                let pb = NSPasteboard.general
                pb.clearContents()
                if let rtf = Note.rtfData(from: source) {
                    pb.setData(rtf, forType: .rtf)
                } else {
                    pb.setString(Note.plainText(from: source), forType: .string)
                }
            }

            Divider()
                .padding(.vertical, 2)

            HeaderActionButton(
                title: l10n["editor.deleteNote"],
                systemName: "trash",
                role: .destructive,
            ) {
                dismiss()
                onDelete()
            }
        }
    }

    private static func getSelectedText() -> String {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              tv.selectedRange().length > 0
        else { return "" }
        return (tv.string as NSString).substring(with: tv.selectedRange())
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
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .contentShape(Rectangle())
        .help(tooltip)
    }
}
