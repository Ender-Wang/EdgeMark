import SwiftUI

struct HomeFolderView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isSearching = false
    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isFolderFieldFocused: Bool

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

    /// Folders sorted by current sort setting.
    private var sortedFolders: [Folder] {
        noteStore.sortedFolders(noteStore.folders, by: appSettings.sortBy, ascending: appSettings.sortAscending)
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
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search notes", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)

                Button(action: dismissSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close Search")
            }
            .onExitCommand { dismissSearch() }
            .opacity(isSearching ? 1 : 0)
            .allowsHitTesting(isSearching)

            // Title bar
            HStack(spacing: 14) {
                Text("EdgeMark")
                    .font(.title2.bold())

                Spacer()

                HeaderIconButton(
                    systemName: "magnifyingglass",
                    help: "Search",
                ) {
                    isSearching = true
                    isSearchFieldFocused = true
                }

                HeaderIconButton(
                    systemName: "folder.badge.plus",
                    help: "New Folder",
                ) {
                    startCreatingFolder()
                }

                HeaderIconButton(
                    systemName: "square.and.pencil",
                    help: "New Note",
                ) {
                    createRootNote()
                }
            }
            .opacity(isSearching ? 0 : 1)
            .allowsHitTesting(!isSearching)
        }
    }

    // MARK: - Folder List

    private var folderDate: (Folder) -> Date? {
        { folder in
            switch appSettings.sortBy {
            case .name: nil
            case .dateModified: folder.latestModifiedAt
            case .dateCreated: folder.earliestCreatedAt
            }
        }
    }

    private var folderList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sortedFolders) { folder in
                    FolderRowView(
                        name: folder.name,
                        count: folder.noteCount,
                        date: folderDate(folder),
                        iconWidth: iconWidth,
                    ) {
                        noteStore.selectedFolder = folder
                    }
                }

                if isCreatingFolder {
                    inlineFolderEditor
                }

                if !rootNotes.isEmpty {
                    if !noteStore.folders.isEmpty || isCreatingFolder {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }

                    ForEach(rootNotes) { note in
                        NoteRowView(
                            note: note,
                            iconWidth: iconWidth,
                        ) {
                            noteStore.selectedNote = note
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: - Inline Folder Editor

    private var inlineFolderEditor: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: iconWidth)

            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFolderFieldFocused)
                .onSubmit { commitNewFolder() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onExitCommand { cancelNewFolder() }
        .onChange(of: isFolderFieldFocused) { _, focused in
            if !focused {
                commitOrCancelFolder()
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            if trimmedQuery.isEmpty {
                emptySearchPlaceholder(
                    icon: "magnifyingglass",
                    message: "Search by title or content",
                )
            } else if !hasAnyResults {
                emptySearchPlaceholder(
                    icon: "doc.questionmark",
                    message: "No results",
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !titleMatches.isEmpty {
                        sectionHeader("Titles")
                        ForEach(titleMatches) { note in
                            titleResultRow(note: note)
                        }
                    }

                    if !contentMatches.isEmpty {
                        sectionHeader("Content")
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
    static func highlightedTitle(_ title: String, query: String) -> AttributedString {
        let displayTitle = title.isEmpty ? "Untitled" : title
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

                    Text(note.folder.isEmpty ? "Root" : note.folder)
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
                    Text(note.title.isEmpty ? "Untitled" : note.title)
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
        if !note.folder.isEmpty {
            noteStore.selectedFolder = Folder(name: note.folder, noteCount: 0)
        }
        noteStore.selectedNote = note
        dismissSearch()
    }

    private func createRootNote() {
        let note = noteStore.createNote()
        noteStore.selectedNote = note
    }

    private func startCreatingFolder() {
        newFolderName = ""
        isCreatingFolder = true
        isFolderFieldFocused = true
    }

    private func commitNewFolder() {
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
        if trimmed.isEmpty {
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
}

// MARK: - Folder Row View

/// Folder row with hover highlight animation.
private struct FolderRowView: View {
    let name: String
    let count: Int
    var date: Date?
    let iconWidth: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: iconWidth)

                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                if let date {
                    Text(date.homeDisplayFormat)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text("\(count)")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 20, alignment: .trailing)
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

    private var previewText: String {
        let lines = note.content.split(separator: "\n", omittingEmptySubsequences: true)
        let bodyLines = lines.dropFirst()
        let raw = bodyLines.prefix(3).joined(separator: " ")
        return raw
            .replacingOccurrences(of: "#{1,6}\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*{1,2}([^*]+)\\*{1,2}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            .prefix(120)
            .description
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(note.createdAt.homeDisplayFormat)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !previewText.isEmpty {
                        Text(previewText)
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
