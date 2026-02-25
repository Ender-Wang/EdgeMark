import SwiftUI

struct HomeFolderView: View {
    @Environment(NoteStore.self) var noteStore
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var isSearching = false
    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool

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

    /// Root-level notes (no folder), sorted by most recently modified.
    private var rootNotes: [Note] {
        noteStore.notes
            .filter(\.folder.isEmpty)
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Section 1: Header card
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background { VisualEffectView() }
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Section 2: Folder list or search results
            ZStack {
                folderList
                    .opacity(isSearching ? 0 : 1)
                    .allowsHitTesting(!isSearching)

                searchResultsList
                    .opacity(isSearching ? 1 : 0)
                    .allowsHitTesting(isSearching)
            }
            .background { VisualEffectView() }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                noteStore.createFolder(named: newFolderName)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
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
                    showNewFolder = true
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

    private var folderList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(noteStore.folders) { folder in
                    folderRow(
                        name: folder.name,
                        count: folder.noteCount,
                        folder: folder,
                    )
                }

                if !rootNotes.isEmpty {
                    if !noteStore.folders.isEmpty {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }

                    ForEach(rootNotes) { note in
                        noteRow(note: note)
                    }
                }
            }
            .padding(.vertical, 10)
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

    // MARK: - Rows

    private func folderRow(name: String, count: Int, folder: Folder) -> some View {
        Button {
            noteStore.selectedFolder = folder
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(count)")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func noteRow(note: Note) -> some View {
        Button {
            noteStore.selectedNote = note
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(note.modifiedAt.homeRelativeFormat)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func titleResultRow(note: Note) -> some View {
        Button {
            openNote(note)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)

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

    private func dismissSearch() {
        isSearchFieldFocused = false
        isSearching = false
        searchQuery = ""
    }
}

// MARK: - Header Icon Button

/// Toolbar icon with hover background animation.
private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(isHovered ? 0.1 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Date Formatting

private extension Date {
    /// Relative format for the home page: "Just now", "5m ago", "2h ago", "Yesterday", or short date.
    var homeRelativeFormat: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: self)
        }
    }
}
