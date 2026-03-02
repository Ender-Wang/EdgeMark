import Cocoa
import SwiftUI

struct HomeFolderView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @Environment(L10n.self) var l10n
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isSearching = false
    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isFolderFieldFocused: Bool

    // Note rename
    @State private var renamingNoteID: UUID?
    @State private var renamingNoteText = ""
    @FocusState private var isNoteRenameFocused: Bool

    // Folder rename
    @State private var renamingFolderName: String?
    @State private var renamingFolderText = ""
    @FocusState private var isFolderRenameFocused: Bool

    // Folder delete confirmation
    @State private var deletingFolderName: String?
    @State private var showDeleteFolderConfirm = false

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Notes whose title contains the query (case-insensitive).
    private var titleMatches: [Note] {
        guard !trimmedQuery.isEmpty else { return [] }
        return noteStore.notes
            .filter { $0.title.range(of: trimmedQuery, options: .caseInsensitive) != nil }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Notes whose content contains the query (case-insensitive). No deduplication — a note
    /// can appear in both Titles and Content sections if it matches both.
    private var contentMatches: [ContentMatch] {
        guard !trimmedQuery.isEmpty else { return [] }
        return noteStore.notes
            .compactMap { note -> ContentMatch? in
                guard let snippet = Self.buildSnippet(content: note.content, query: trimmedQuery) else {
                    return nil
                }
                return ContentMatch(note: note, snippet: snippet)
            }
            .sorted { $0.note.modifiedAt > $1.note.modifiedAt }
    }

    /// Wrapper to give content matches a unique ID (prefixed) so they don't collide
    /// with title matches when the same note appears in both ForEach loops.
    private struct ContentMatch: Identifiable {
        var id: String {
            "content-\(note.id)"
        }

        let note: Note
        let snippet: AttributedString
    }

    private var hasAnyResults: Bool {
        !titleMatches.isEmpty || !contentMatches.isEmpty
    }

    /// Root-level notes (no folder), sorted by current sort setting.
    private var rootNotes: [Note] {
        let filtered = noteStore.notes.filter(\.folder.isEmpty)
        return noteStore.sortedNotes(filtered, by: appSettings.sortBy, ascending: appSettings.sortAscending)
    }

    /// Top-level folders sorted by current sort setting.
    private var sortedFolders: [Folder] {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
        return noteStore.sortedFolders(topLevel, by: appSettings.sortBy, ascending: appSettings.sortAscending)
    }

    // MARK: - Icon width

    /// Fixed width for leading icons so folder and note icons align.
    private let iconWidth: CGFloat = 22

    var body: some View {
        PageLayout {
            header
        } content: {
            VStack(spacing: 0) {
                ZStack {
                    folderList
                        .opacity(isSearching ? 0 : 1)
                        .allowsHitTesting(!isSearching)

                    searchResultsList
                        .opacity(isSearching ? 1 : 0)
                        .allowsHitTesting(isSearching)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
            }
        }
        .moveConflictAlerts(noteStore: noteStore, l10n: l10n)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(l10n["search.placeholder"], text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)

                Button(action: dismissSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(l10n["search.close"])
            }
            .onExitCommand { dismissSearch() }
            .opacity(isSearching ? 1 : 0)
            .allowsHitTesting(isSearching)

            // Title bar
            HStack {
                Text(l10n["home.title"])
                    .font(.title2.bold())

                Spacer()

                HeaderIconButton(
                    systemName: "magnifyingglass",
                    help: l10n["common.search"],
                ) {
                    isSearching = true
                    isSearchFieldFocused = true
                }

                HeaderIconButton(
                    systemName: "folder.badge.plus",
                    help: l10n["common.newFolder"],
                ) {
                    startCreatingFolder()
                }

                HeaderIconButton(
                    systemName: "square.and.pencil",
                    help: l10n["common.newNote"],
                ) {
                    createRootNote()
                }
            }
            .opacity(isSearching ? 0 : 1)
            .allowsHitTesting(!isSearching)
        }
    }

    // MARK: - Folder List

    private var folderList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sortedFolders) { folder in
                    folderRowWithContextMenu(folder: folder)
                }

                if isCreatingFolder {
                    inlineFolderEditor
                }

                if !rootNotes.isEmpty {
                    if !sortedFolders.isEmpty || isCreatingFolder {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }

                    ForEach(rootNotes) { note in
                        noteRowWithContextMenu(note: note)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .alert(
            l10n["alert.deleteFolder.title"],
            isPresented: $showDeleteFolderConfirm,
            presenting: deletingFolderName,
        ) { folderName in
            Button(l10n["common.cancel"], role: .cancel) {}
            Button(l10n["common.delete"], role: .destructive) {
                noteStore.trashFolder(folderName)
            }
        } message: { folderName in
            let prefix = folderName + "/"
            let count = noteStore.notes.count(where: { $0.folder == folderName || $0.folder.hasPrefix(prefix) })
            if count > 0 {
                Text(l10n.t("alert.deleteFolder.withNotes", folderName, "\(count)"))
            } else {
                Text(l10n.t("alert.deleteFolder.empty", folderName))
            }
        }
    }

    // MARK: - Inline Folder Editor

    private var newFolderNameConflicts: Bool {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return noteStore.folders.contains {
            $0.isTopLevel && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var noteRenameConflicts: Bool {
        let trimmed = renamingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let noteID = renamingNoteID else { return false }
        let folder = noteStore.notes.first(where: { $0.id == noteID })?.folder ?? ""
        return noteStore.noteTitleExists(trimmed, in: folder, excluding: noteID)
    }

    private var folderRenameConflicts: Bool {
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let oldName = renamingFolderName else { return false }
        return noteStore.folders.contains {
            $0.name != oldName && $0.isTopLevel
                && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var inlineFolderEditor: some View {
        InlineRenameEditor(
            icon: "folder.fill",
            iconColor: .accentColor,
            placeholder: l10n["common.folderNamePlaceholder"],
            text: $newFolderName,
            isFocused: $isFolderFieldFocused,
            isConflicting: newFolderNameConflicts,
            iconWidth: iconWidth,
            onCommit: { commitNewFolder() },
            onCancel: { cancelNewFolder() },
            onFocusLost: { commitOrCancelFolder() },
        )
    }

    // MARK: - Folder Row with Context Menu

    @ViewBuilder
    private func folderRowWithContextMenu(folder: Folder) -> some View {
        if renamingFolderName == folder.name {
            inlineFolderRenameEditor(folderName: folder.name)
        } else {
            FolderRowView(
                name: folder.name,
                count: folder.noteCount,
                date: appSettings.folderDate(for: folder),
                iconWidth: iconWidth,
            ) {
                noteStore.navigateToFolder(folder)
            }
            .nsContextMenu {
                NoteListMenus.folderMenu(
                    folder: folder,
                    noteStore: noteStore,
                    l10n: l10n,
                    onRename: { startRenamingFolder(folder.name) },
                    onDelete: {
                        deletingFolderName = folder.name
                        showDeleteFolderConfirm = true
                    },
                )
            }
        }
    }

    // MARK: - Note Row with Context Menu

    @ViewBuilder
    private func noteRowWithContextMenu(note: Note) -> some View {
        if renamingNoteID == note.id {
            inlineNoteRenameEditor(note: note)
        } else {
            NoteRowView(
                note: note,
                iconWidth: iconWidth,
            ) {
                noteStore.openNote(note)
            }
            .nsContextMenu {
                NoteListMenus.noteMenu(
                    note: note,
                    noteStore: noteStore,
                    l10n: l10n,
                    onRename: { startRenamingNote(note) },
                )
            }
        }
    }

    // MARK: - Inline Note Rename Editor

    private func inlineNoteRenameEditor(note: Note) -> some View {
        InlineRenameEditor(
            icon: "doc.text",
            placeholder: l10n["common.noteTitlePlaceholder"],
            text: $renamingNoteText,
            isFocused: $isNoteRenameFocused,
            isConflicting: noteRenameConflicts,
            iconWidth: iconWidth,
            onCommit: { commitNoteRename(note) },
            onCancel: { cancelNoteRename() },
            onFocusLost: { commitOrCancelNoteRename(note) },
        )
    }

    // MARK: - Inline Folder Rename Editor

    private func inlineFolderRenameEditor(folderName: String) -> some View {
        InlineRenameEditor(
            icon: "folder.fill",
            iconColor: .accentColor,
            placeholder: l10n["common.folderNamePlaceholder"],
            text: $renamingFolderText,
            isFocused: $isFolderRenameFocused,
            isConflicting: folderRenameConflicts,
            iconWidth: iconWidth,
            onCommit: { commitFolderRename(folderName) },
            onCancel: { cancelFolderRename() },
            onFocusLost: { commitOrCancelFolderRename(folderName) },
        )
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            if trimmedQuery.isEmpty {
                emptySearchPlaceholder(
                    icon: "magnifyingglass",
                    message: l10n["search.hint"],
                )
            } else if !hasAnyResults {
                emptySearchPlaceholder(
                    icon: "doc.questionmark",
                    message: l10n["search.noResults"],
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !titleMatches.isEmpty {
                        sectionHeader(l10n["search.titles"])
                        ForEach(titleMatches) { note in
                            titleResultRow(note: note)
                        }
                    }

                    if !contentMatches.isEmpty {
                        sectionHeader(l10n["search.content"])
                        ForEach(contentMatches) { match in
                            contentResultRow(note: match.note, snippet: match.snippet)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Helpers

    private func emptySearchPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    /// Build an attributed title with the matched portion highlighted in bold orange.
    static func highlightedTitle(_ title: String, query: String, untitled: String = L10n.shared["common.untitled"]) -> AttributedString {
        let displayTitle = title.isEmpty ? untitled : title
        var attributed = AttributedString(displayTitle)
        attributed.foregroundColor = .primary
        if let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = .orange
        }
        return attributed
    }

    /// Build an attributed snippet with ~40 chars of context around the first match, highlighted in bold orange.
    static func buildSnippet(content: String, query: String) -> AttributedString? {
        guard let range = content.range(of: query, options: .caseInsensitive) else {
            return nil
        }

        // Context window: ~40 chars before and after the match, using String indices directly
        let contextChars = 40
        let snippetLower = content.index(
            range.lowerBound,
            offsetBy: -contextChars,
            limitedBy: content.startIndex,
        ) ?? content.startIndex
        let snippetUpper = content.index(
            range.upperBound,
            offsetBy: contextChars,
            limitedBy: content.endIndex,
        ) ?? content.endIndex

        var snippetText = String(content[snippetLower ..< snippetUpper])
            .replacingOccurrences(of: "\n", with: " ")

        if snippetLower > content.startIndex { snippetText = "…" + snippetText }
        if snippetUpper < content.endIndex { snippetText += "…" }

        // Highlight the matched portion
        var attributed = AttributedString(snippetText)
        if let attrRange = attributed.range(of: query, options: .caseInsensitive) {
            attributed[attrRange].font = .caption.bold()
            attributed[attrRange].foregroundColor = .orange
        }
        return attributed
    }

    // MARK: - Search Result Rows

    private func titleResultRow(note: Note) -> some View {
        Button {
            openNote(note)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.highlightedTitle(note.title, query: trimmedQuery))
                        .font(.body)
                        .lineLimit(1)

                    Text(note.folder.isEmpty ? L10n.shared["common.root"] : note.folder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func contentResultRow(note: Note, snippet: AttributedString) -> some View {
        Button {
            openNote(note)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? L10n.shared["common.untitled"] : note.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openNote(_ note: Note) {
        dismissSearch()
        noteStore.openNoteFromSearch(note)
    }

    private func createRootNote() {
        noteStore.createAndOpenNote()
    }

    private func startCreatingFolder() {
        newFolderName = ""
        isCreatingFolder = true
        isFolderFieldFocused = true
    }

    private func commitNewFolder() {
        guard !newFolderNameConflicts else { return }
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            noteStore.createFolder(named: trimmed)
        }
        isCreatingFolder = false
        newFolderName = ""
    }

    private func cancelNewFolder() {
        isCreatingFolder = false
        newFolderName = ""
    }

    private func commitOrCancelFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || newFolderNameConflicts {
            cancelNewFolder()
        } else {
            commitNewFolder()
        }
    }

    private func dismissSearch() {
        isSearchFieldFocused = false
        isSearching = false
        searchQuery = ""
    }

    // MARK: - Note Rename Actions

    private func startRenamingNote(_ note: Note) {
        renamingNoteID = note.id
        renamingNoteText = note.title
        DispatchQueue.main.async {
            isNoteRenameFocused = true
        }
    }

    private func commitNoteRename(_ note: Note) {
        guard !noteRenameConflicts else { return }
        let trimmed = renamingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != note.title {
            noteStore.renameNote(note, to: trimmed)
        }
        renamingNoteID = nil
        renamingNoteText = ""
    }

    private func cancelNoteRename() {
        renamingNoteID = nil
        renamingNoteText = ""
    }

    private func commitOrCancelNoteRename(_ note: Note) {
        let trimmed = renamingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || noteRenameConflicts {
            cancelNoteRename()
        } else {
            commitNoteRename(note)
        }
    }

    // MARK: - Folder Rename Actions

    private func startRenamingFolder(_ name: String) {
        renamingFolderName = name
        renamingFolderText = name
        DispatchQueue.main.async {
            isFolderRenameFocused = true
        }
    }

    private func commitFolderRename(_ oldName: String) {
        guard !folderRenameConflicts else { return }
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != oldName {
            noteStore.renameFolder(oldName, to: trimmed)
        }
        renamingFolderName = nil
        renamingFolderText = ""
    }

    private func cancelFolderRename() {
        renamingFolderName = nil
        renamingFolderText = ""
    }

    private func commitOrCancelFolderRename(_ oldName: String) {
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || folderRenameConflicts {
            cancelFolderRename()
        } else {
            commitFolderRename(oldName)
        }
    }
}

// MARK: - Folder Row View

/// Folder row with hover highlight animation.
struct FolderRowView: View {
    let name: String
    let count: Int
    var date: Date?
    let iconWidth: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)

                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.background)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(.primary.opacity(0.8), in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
                .frame(width: iconWidth)

                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if let date {
                    Text(date.homeDisplayFormat)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Note Row View

/// Note row with hover highlight animation and preview line.
struct NoteRowView: View {
    let note: Note
    let iconWidth: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(note.title.isEmpty ? L10n.shared["common.untitled"] : note.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(note.createdAt.homeDisplayFormat)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !note.previewText.isEmpty {
                        Text(note.previewText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
