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
            .opacity(isSearching ? 1 : 0)
            .allowsHitTesting(isSearching)

            // Title bar
            HStack {
                Text("EdgeMark")
                    .font(.title2.bold())

                Spacer()

                Button(action: {
                    isSearching = true
                    isSearchFieldFocused = true
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Search")

                Button(action: { showNewFolder = true }) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("New Folder")
            }
            .opacity(isSearching ? 0 : 1)
            .allowsHitTesting(!isSearching)
        }
    }

    // MARK: - Folder List

    private var folderList: some View {
        ScrollView {
            VStack(spacing: 0) {
                folderRow(
                    name: "All Notes",
                    count: noteStore.notes.count,
                    folder: .allNotes,
                )

                ForEach(noteStore.folders) { folder in
                    folderRow(
                        name: folder.name,
                        count: folder.noteCount,
                        folder: folder,
                    )
                }
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

                    Text(note.folder.isEmpty ? "All Notes" : note.folder)
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
        let folder: Folder = if note.folder.isEmpty {
            .allNotes
        } else {
            Folder(name: note.folder, noteCount: 0)
        }
        noteStore.selectedFolder = folder
        noteStore.selectedNote = note
        dismissSearch()
    }

    private func dismissSearch() {
        isSearchFieldFocused = false
        isSearching = false
        searchQuery = ""
    }
}
