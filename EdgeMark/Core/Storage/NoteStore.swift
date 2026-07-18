import Foundation
import OSLog
import SwiftUI

@Observable
final class NoteStore {
    // MARK: - State

    var notes: [Note] = []
    var trashedNotes: [Note] = []
    var trashedFolders: [TrashedFolder] = []
    var folders: [Folder] = []
    var selectedFolder: Folder?
    var selectedNote: Note?
    var showTrash = false

    /// Set at launch when "Choose on launch" is on and ≥2 storage roots are configured.
    /// While true, the panel shows a non-blocking storage-root picker instead of the
    /// note list; picking a root clears this and switches (temporary) to that root.
    var awaitingRootChoice: Bool = false

    // MARK: - List Selection (multi-select)

    /// Identity for a row in the note list. Notes use UUID; folders use path.
    enum SelectableID: Hashable {
        case note(UUID)
        case folder(String)
    }

    /// What's selected in the visible list — distinct from `selectedNote` /
    /// `selectedFolder` (which represent what's *open*). Empty after navigation.
    var selection: Set<SelectableID> = []

    /// Anchor row for ⇧-click range selection.
    private var selectionAnchor: SelectableID?

    /// The "active end" of a shift-extended range — walks with ⇧-arrow / ⇧-click
    /// while `selectionAnchor` stays put. Equals anchor for non-extended selections.
    private var selectionExtensionEnd: SelectableID?

    // MARK: - Navigation Direction

    enum NavigationDirection {
        case forward
        case backward
        case overlay
        case none
    }

    var navigationDirection: NavigationDirection = .none

    /// Pending note moves that have name conflicts at the destination.
    /// The first element is the active conflict shown by the UI; remaining elements
    /// queue up so a batch move surfaces every collision sequentially instead of dropping
    /// all but the last.
    struct PendingNoteMoveConflict {
        let noteID: UUID
        let targetFolder: String
    }

    var pendingNoteMoveConflicts: [PendingNoteMoveConflict] = []

    /// Pending folder moves that have name conflicts at the destination. Same queue semantics as notes.
    struct PendingFolderMoveConflict {
        let folderName: String
        let targetParent: String
    }

    var pendingFolderMoveConflicts: [PendingFolderMoveConflict] = []

    /// Conflict when both EdgeMark and an external editor modified the same open note.
    struct PendingExternalChange {
        let noteID: UUID
        let diskContent: String
        let diskDate: Date
        let diskTags: [TagColor]
    }

    var pendingExternalChange: PendingExternalChange?

    /// Called when an open note is auto-synced from disk — pushes new content directly to the editor.
    var onNeedEditorReload: ((String) -> Void)?

    /// Cached set of folder paths that exist on disk (including empty folders).
    /// Updated only by disk-mutating folder operations — avoids a full filesystem
    /// enumeration on every `refreshFolders()` call.
    private var diskFolderNames: Set<String> = []

    /// Set to true to trigger the search bar on HomeFolderView after navigating back.
    var pendingSearchOnHome = false
    /// Set to true by the shortcut handler to trigger "new folder" in the currently visible list view.
    var pendingNewFolder = false
    /// Set by shortcut handler after creating a note to trigger inline rename in the list view.
    var pendingRenameNote: Note?
    /// Set to true by the ⌘F shortcut handler when a note is open — consumed by EditorScreen
    /// to show the in-editor find bar.
    var pendingEditorFind: Bool = false

    /// Folder to return to when the user dismisses search (set when search is triggered from a subfolder).
    var searchReturnFolder: Folder?

    /// Active tag filter applied within the search experience. Session-only; cleared on dismiss.
    var activeTagFilter: Set<TagColor> = []

    /// Cached set of tag colors in use across all active notes. Avoids an O(N×T)
    /// recomputation on every TagFilterBar render. Updated by the handful of
    /// mutators that touch tags.
    private(set) var allUsedTags: Set<TagColor> = []

    private func recomputeAllUsedTags() {
        allUsedTags = Set(notes.flatMap(\.tags))
    }

    /// Notes filtered by selected folder (unsorted — views apply sort via `sortedNotes`).
    var filteredNotes: [Note] {
        if let folder = selectedFolder {
            notes.filter { $0.folder == folder.name }
        } else {
            notes
        }
    }

    // MARK: - Sorting

    func sortedNotes(_ notes: [Note], by sortBy: AppSettings.SortBy, ascending: Bool) -> [Note] {
        notes.sorted { a, b in
            let result: Bool = switch sortBy {
            case .name:
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .dateModified:
                a.modifiedAt < b.modifiedAt
            case .dateCreated:
                a.createdAt < b.createdAt
            }
            return ascending ? result : !result
        }
    }

    func sortedFolders(_ folders: [Folder], by sortBy: AppSettings.SortBy, ascending: Bool) -> [Folder] {
        folders.sorted { a, b in
            let result: Bool = switch sortBy {
            case .name:
                a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .dateModified:
                // nil dates (empty folders) sort to end
                switch (a.latestModifiedAt, b.latestModifiedAt) {
                case let (aDate?, bDate?): aDate < bDate
                case (nil, _): false
                case (_, nil): true
                }
            case .dateCreated:
                switch (a.earliestCreatedAt, b.earliestCreatedAt) {
                case let (aDate?, bDate?): aDate < bDate
                case (nil, _): false
                case (_, nil): true
                }
            }
            return ascending ? result : !result
        }
    }

    // MARK: - Animated Navigation

    func navigateToHome() {
        Log.navigation.debug("[NoteStore] navigateToHome")
        navigationDirection = .backward
        clearSelection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = nil
            selectedFolder = nil
        }
    }

    func navigateToFolder(_ folder: Folder) {
        let name = folder.name
        Log.navigation.debug("[NoteStore] navigateToFolder — \(name, privacy: .public)")
        navigationDirection = .forward
        clearSelection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedFolder = folder
        }
    }

    func navigateToSubfolder(_ folder: Folder) {
        let name = folder.name
        Log.navigation.debug("[NoteStore] navigateToSubfolder — \(name, privacy: .public)")
        navigationDirection = .forward
        clearSelection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedFolder = folder
        }
    }

    func navigateBack() {
        let from = selectedNote?.title ?? selectedFolder?.name ?? "home"
        Log.navigation.debug("[NoteStore] navigateBack from \(from, privacy: .public)")
        navigationDirection = .backward
        clearSelection()
        if selectedNote != nil {
            saveDirtyNotes()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNote = nil
            }
        } else if let parent = selectedFolder?.parentPath, !parent.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolder = folders.first { $0.name == parent }
                    ?? Folder(name: parent, noteCount: 0)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolder = nil
            }
        }
    }

    func openNote(_ note: Note) {
        let title = note.title
        Log.navigation.debug("[NoteStore] openNote — \(title, privacy: .public)")
        navigationDirection = .forward
        clearSelection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = note
        }
    }

    func openNoteFromSearch(_ note: Note) {
        let title = note.title
        let folder = note.folder
        Log.navigation.debug("[NoteStore] openNoteFromSearch — \(title, privacy: .public) in \(folder, privacy: .public)")
        if !note.folder.isEmpty {
            selectedFolder = Folder(name: note.folder, noteCount: 0)
        }
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = note
        }
    }

    func closeNote() {
        let title = selectedNote?.title ?? "nil"
        Log.navigation.debug("[NoteStore] closeNote — \(title, privacy: .public)")
        navigationDirection = .backward
        saveDirtyNotes()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = nil
        }
    }

    /// Notes in the current folder only (not descendants). Root = notes with empty folder.
    private var currentFolderNotes: [Note] {
        if let folder = selectedFolder {
            notes.filter { $0.folder == folder.name }
        } else {
            notes.filter(\.folder.isEmpty)
        }
    }

    func navigateToNextNote(sortedBy appSettings: AppSettings) {
        guard let current = selectedNote else { return }
        let sorted = sortedNotes(currentFolderNotes, by: appSettings.sortBy, ascending: appSettings.sortAscending)
        guard let index = sorted.firstIndex(where: { $0.id == current.id }),
              index + 1 < sorted.count
        else { return }
        let next = sorted[index + 1]
        let title = next.title
        Log.navigation.debug("[NoteStore] navigateToNextNote — \(title, privacy: .public)")
        saveDirtyNotes()
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = next
        }
    }

    func navigateToPreviousNote(sortedBy appSettings: AppSettings) {
        guard let current = selectedNote else { return }
        let sorted = sortedNotes(currentFolderNotes, by: appSettings.sortBy, ascending: appSettings.sortAscending)
        guard let index = sorted.firstIndex(where: { $0.id == current.id }),
              index > 0
        else { return }
        let prev = sorted[index - 1]
        let title = prev.title
        Log.navigation.debug("[NoteStore] navigateToPreviousNote — \(title, privacy: .public)")
        saveDirtyNotes()
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = prev
        }
    }

    func openTrash() {
        Log.navigation.debug("[NoteStore] openTrash")
        navigationDirection = .overlay
        clearSelection()
        withAnimation(.easeInOut(duration: 0.2)) {
            showTrash = true
        }
    }

    func closeTrash() {
        Log.navigation.debug("[NoteStore] closeTrash")
        navigationDirection = .overlay
        clearSelection()
        withAnimation(.easeInOut(duration: 0.2)) {
            showTrash = false
        }
    }

    // MARK: - Dirty Tracking

    private var dirtyNoteIDs: Set<UUID> = []

    // MARK: - Lifecycle

    func loadFromDisk() {
        do {
            let loaded = try FileStorage.loadAllNotes()
            // Auto-correct duplicate UUIDs — reassign a new UUID to any duplicate and re-save
            // to disk so both notes survive (e.g. user copied a .md file in Finder)
            var seen = Set<UUID>()
            notes = loaded.map { note in
                guard seen.insert(note.id).inserted else {
                    let newID = UUID()
                    Log.storage.warning("[NoteStore] duplicate UUID '\(note.id)' for '\(note.title, privacy: .public)' — reassigning to \(newID)")
                    let fixed = Note(
                        id: newID,
                        title: note.title,
                        content: note.content,
                        createdAt: note.createdAt,
                        modifiedAt: note.modifiedAt,
                        savedAt: note.savedAt,
                        folder: note.folder,
                        trashedAt: note.trashedAt,
                        savedFilename: note.savedFilename,
                    )
                    do {
                        try FileStorage.writeNote(fixed) // return value intentionally discarded (dedup path)
                    } catch {
                        Log.storage.error("[NoteStore] failed to re-save deduped note — \(error)")
                    }
                    return fixed
                }
                return note
            }
            trashedNotes = try FileStorage.loadTrashedNotes()
            trashedFolders = try FileStorage.loadTrashedFolders()
            autoPurgeExpiredTrash()
            diskFolderNames = Set((try? FileStorage.discoverFolders()) ?? [])
            refreshFolders()
            let noteCount = notes.count
            let trashCount = trashedNotes.count + trashedFolders.count
            Log.storage.info("[NoteStore] loaded \(noteCount) notes, \(trashCount) trashed items")
        } catch {
            Log.storage.error("[NoteStore] loadFromDisk failed — \(error)")
        }
    }

    /// Called on every app foreground transition. Checks each note for external modifications
    /// and reloads or prompts based on dirty state.
    func checkForExternalChanges() {
        let count = notes.count
        Log.storage.debug("[ExternalSync] checking \(count) notes")
        for i in notes.indices {
            let note = notes[i]
            guard let diskDate = FileStorage.modificationDate(for: note) else {
                let t = note.title
                Log.storage.debug("[ExternalSync] '\(t, privacy: .public)' — file not found on disk")
                continue
            }
            // Compare file mtime against savedAt (last time EdgeMark wrote this file).
            // Using savedAt instead of modifiedAt prevents false positives from auto-saves
            // that write the file without changing content.
            let diff = diskDate.timeIntervalSince(note.savedAt)
            let t = note.title
            Log.storage.debug("[ExternalSync] '\(t, privacy: .public)' — diff: \(String(format: "%.3f", diff))s")
            guard diff > 1 else { continue }

            let noteID = notes[i].id
            let isOpen = selectedNote?.id == noteID
            let isDirty = dirtyNoteIDs.contains(noteID)

            guard let reloaded = FileStorage.reloadContent(for: notes[i]) else { continue }
            let diskContent = reloaded.content
            let diskModifiedAt = reloaded.modifiedAt
            let diskSavedAt = reloaded.savedAt
            let diskTags = reloaded.tags

            let title = notes[i].title
            if isOpen, isDirty {
                // Both EdgeMark and external have changes — prompt user
                Log.storage.info("[NoteStore] external conflict on open note '\(title, privacy: .public)'")
                pendingExternalChange = PendingExternalChange(noteID: noteID, diskContent: diskContent, diskDate: diskDate, diskTags: diskTags)
            } else {
                // Safe to auto-reload: note not open, or open but no EdgeMark edits
                Log.storage.info("[NoteStore] auto-syncing '\(title, privacy: .public)' from external change")
                notes[i].content = diskContent
                notes[i].modifiedAt = diskModifiedAt
                notes[i].savedAt = diskSavedAt
                notes[i].tags = diskTags
                dirtyNoteIDs.remove(noteID)
                // Persist updated savedAt to sidecar so the watcher doesn't re-fire on next launch
                if var entry = SidecarStore.shared.noteEntry(for: noteID) {
                    entry.savedAt = diskSavedAt
                    entry.modifiedAt = diskModifiedAt
                    entry.tags = diskTags.map(\.rawValue)
                    SidecarStore.shared.upsertNote(entry, for: noteID)
                    try? SidecarStore.shared.save()
                }
                if isOpen {
                    selectedNote = notes[i]
                    onNeedEditorReload?(diskContent)
                }
                recomputeAllUsedTags()
            }
        }
    }

    /// Resolve external conflict: keep EdgeMark edits (discard disk) or reload from disk.
    func resolveExternalChange(keepEdgeMarkEdits: Bool) {
        guard let conflict = pendingExternalChange else { return }
        pendingExternalChange = nil
        if !keepEdgeMarkEdits,
           let i = notes.firstIndex(where: { $0.id == conflict.noteID })
        {
            notes[i].content = conflict.diskContent
            notes[i].modifiedAt = conflict.diskDate
            notes[i].savedAt = conflict.diskDate
            notes[i].tags = conflict.diskTags
            dirtyNoteIDs.remove(conflict.noteID)
            // Persist updated savedAt + tags so the watcher doesn't re-fire on next launch
            if var entry = SidecarStore.shared.noteEntry(for: conflict.noteID) {
                entry.savedAt = conflict.diskDate
                entry.modifiedAt = conflict.diskDate
                entry.tags = conflict.diskTags.map(\.rawValue)
                SidecarStore.shared.upsertNote(entry, for: conflict.noteID)
                try? SidecarStore.shared.save()
            }
            recomputeAllUsedTags()
            if selectedNote?.id == conflict.noteID {
                selectedNote = notes[i]
                onNeedEditorReload?(conflict.diskContent)
            }
        }
    }

    // MARK: - Duplicate Detection

    /// Whether a note title already exists in the given folder (case-insensitive filename match).
    func noteTitleExists(_ title: String, in folder: String, excluding noteID: UUID? = nil) -> Bool {
        let sanitized = FileStorage.sanitizeForFilename(title)
        return notes.contains { note in
            note.id != noteID
                && note.folder == folder
                && FileStorage.sanitizeForFilename(note.title).caseInsensitiveCompare(sanitized) == .orderedSame
        }
    }

    /// Effective on-disk filename for a note (savedFilename if set, else title-derived).
    /// `noteTitleExists` is purely title-based and misses the case where a title was
    /// renamed in memory but `savedFilename` still points at the old on-disk name — or
    /// where an orphan `.md` file exists in the destination directory. The move path
    /// must use this helper to avoid the OS-level NSCocoaErrorDomain 516 leaking through.
    private func noteFilenameWouldCollide(_ filename: String, in folder: String, excluding noteID: UUID? = nil) -> Bool {
        let collidesInMemory = notes.contains { other in
            other.id != noteID
                && other.folder == folder
                && (other.savedFilename ?? other.filename).caseInsensitiveCompare(filename) == .orderedSame
        }
        if collidesInMemory {
            return true
        }
        let destURL = folder.isEmpty
            ? FileStorage.rootURL.appendingPathComponent(filename)
            : FileStorage.rootURL.appendingPathComponent(folder).appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: destURL.path)
    }

    /// Symmetric helper for folder moves — catches in-memory sibling clashes plus
    /// orphan directories on disk that aren't tracked in `folders`. Without the
    /// filesystem check, `moveFolder` would skip the conflict alert and fall through
    /// to `FileStorage.moveFolder`, where macOS surfaces NSCocoaErrorDomain 516.
    private func folderWouldCollide(displayName: String, in newParent: String, excluding folderPath: String? = nil) -> Bool {
        let siblings = newParent.isEmpty
            ? folders.filter(\.isTopLevel)
            : childFolders(of: newParent)
        let collidesInMemory = siblings.contains { sib in
            sib.name != folderPath
                && sib.displayName.caseInsensitiveCompare(displayName) == .orderedSame
        }
        if collidesInMemory {
            return true
        }
        let destURL = newParent.isEmpty
            ? FileStorage.rootURL.appendingPathComponent(displayName)
            : FileStorage.rootURL.appendingPathComponent(newParent).appendingPathComponent(displayName)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destURL.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    // MARK: - Note CRUD

    func createNote(in folder: String = "") -> Note {
        var title = "Untitled"
        var counter = 2
        while noteTitleExists(title, in: folder) {
            title = "Untitled \(counter)"
            counter += 1
        }
        let now = Date()
        var note = Note(
            id: UUID(),
            title: title,
            content: "# \(title)\n\n",
            createdAt: now,
            modifiedAt: now,
            folder: folder,
        )
        do {
            let result = try FileStorage.writeNote(note)
            note.savedFilename = result.filename
            note.savedAt = result.savedAt
        } catch {
            Log.storage.error("[NoteStore] writeNote failed — \(error)")
        }
        notes.append(note)
        refreshFolders()
        return note
    }

    func updateContent(for noteID: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        guard notes[index].content != content else { return }
        notes[index].content = content
        notes[index].modifiedAt = Date()
        // Only derive title from content when an explicit # heading is present.
        // Without this guard, a rename on a headingless note reverts within ~150ms
        // because the editor fires contentChanged on load and extractTitle returns
        // the raw first line, overwriting the manually-set title.
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        if firstLine.hasPrefix("#") {
            notes[index].title = Self.extractTitle(from: content)
        }
        dirtyNoteIDs.insert(noteID)

        // Also update selectedNote if it matches
        if selectedNote?.id == noteID {
            selectedNote = notes[index]
        }
    }

    func renameNote(_ note: Note, to newTitle: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !noteTitleExists(trimmed, in: note.folder, excluding: note.id) else { return }

        notes[index].title = trimmed
        notes[index].modifiedAt = Date()

        // Update the first # heading line in content to match the new title
        var lines = notes[index].content.components(separatedBy: "\n")
        if let headingIndex = lines.firstIndex(where: { $0.hasPrefix("#") }) {
            let prefix = String(lines[headingIndex].prefix(while: { $0 == "#" }))
            lines[headingIndex] = "\(prefix) \(trimmed)"
            notes[index].content = lines.joined(separator: "\n")
        }

        dirtyNoteIDs.insert(note.id)

        if selectedNote?.id == note.id {
            selectedNote = notes[index]
        }
    }

    /// Toggle a single tag on a note. Updates in-memory state and marks the note dirty.
    func toggleTag(_ tag: TagColor, on note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        if let i = notes[index].tags.firstIndex(of: tag) {
            notes[index].tags.remove(at: i)
        } else {
            notes[index].tags.append(tag)
        }
        notes[index].modifiedAt = Date()
        dirtyNoteIDs.insert(note.id)
        if selectedNote?.id == note.id {
            selectedNote = notes[index]
        }
        recomputeAllUsedTags()
    }

    /// Toggle a tag in the active sidebar filter. Multi-select acts as OR.
    func toggleTagFilter(_ tag: TagColor) {
        // Filter change → visible row set may shrink; selection would point at hidden rows.
        clearSelection()
        if activeTagFilter.contains(tag) {
            activeTagFilter.remove(tag)
        } else {
            activeTagFilter.insert(tag)
        }
    }

    func clearTagFilter() {
        activeTagFilter.removeAll()
    }

    // MARK: - Selection actions

    func isSelected(_ id: SelectableID) -> Bool {
        selection.contains(id)
    }

    /// Mouse-driven selection handler matching Finder semantics.
    /// `visibleOrder` is the current flat row order used for ⇧-click ranges.
    func handleSelectionClick(
        on item: SelectableID,
        isShift: Bool,
        isCommand: Bool,
        visibleOrder: [SelectableID],
    ) {
        if isCommand {
            if selection.contains(item) {
                selection.remove(item)
            } else {
                selection.insert(item)
            }
            selectionAnchor = item
            selectionExtensionEnd = item
        } else if isShift,
                  let anchor = selectionAnchor,
                  let a = visibleOrder.firstIndex(of: anchor),
                  let b = visibleOrder.firstIndex(of: item)
        {
            let lo = min(a, b)
            let hi = max(a, b)
            selection = Set(visibleOrder[lo ... hi])
            selectionExtensionEnd = item
        } else {
            selection = [item]
            selectionAnchor = item
            selectionExtensionEnd = item
        }
    }

    /// Replace selection with a single item (used when right-clicking an unselected row).
    func replaceSelection(with item: SelectableID) {
        selection = [item]
        selectionAnchor = item
        selectionExtensionEnd = item
    }

    func clearSelection() {
        selection.removeAll()
        selectionAnchor = nil
        selectionExtensionEnd = nil
    }

    // MARK: - Keyboard navigation

    /// Flat row order matching what the active list view is rendering.
    /// Empty when keyboard navigation shouldn't apply (editor, trash).
    var keyboardNavOrder: [SelectableID] {
        if selectedNote != nil || showTrash {
            return []
        }
        let s = AppSettings.shared
        if let parent = selectedFolder?.name {
            let kidFolders = sortedFolders(childFolders(of: parent), by: s.sortBy, ascending: s.sortAscending)
            let folderNotes = sortedNotes(filteredNotes, by: s.sortBy, ascending: s.sortAscending)
            return kidFolders.map { .folder($0.name) } + folderNotes.map { .note($0.id) }
        }
        let topLevel = sortedFolders(folders.filter(\.isTopLevel), by: s.sortBy, ascending: s.sortAscending)
        let rootNotes = sortedNotes(notes.filter(\.folder.isEmpty), by: s.sortBy, ascending: s.sortAscending)
        return topLevel.map { .folder($0.name) } + rootNotes.map { .note($0.id) }
    }

    /// Move the selection one row down (or up). When `extending` is true,
    /// walk the active end from the anchor (⇧-arrow); otherwise replace with a single item.
    /// Returns true if the keystroke was consumed.
    @discardableResult
    func moveSelection(direction: Int, extending: Bool) -> Bool {
        let order = keyboardNavOrder
        guard !order.isEmpty else { return false }

        // Cursor walks `selectionExtensionEnd` for ⇧-arrows so each press advances
        // by one. Falls back to anchor / first selected row when state is missing.
        let cursor = selectionExtensionEnd ?? selectionAnchor ?? selection.first

        // No prior cursor (or it points at a hidden row) — land on first/last.
        guard let cursor, let idx = order.firstIndex(of: cursor) else {
            let target = direction > 0 ? order.first! : order.last!
            selection = [target]
            selectionAnchor = target
            selectionExtensionEnd = target
            return true
        }

        let next = max(0, min(order.count - 1, idx + direction))
        let target = order[next]

        if extending {
            // Anchor stays put; only the extension end walks.
            let anchor = selectionAnchor ?? cursor
            guard let a = order.firstIndex(of: anchor) else {
                selection = [target]
                selectionAnchor = target
                selectionExtensionEnd = target
                return true
            }
            let lo = min(a, next)
            let hi = max(a, next)
            selection = Set(order[lo ... hi])
            selectionExtensionEnd = target
        } else {
            selection = [target]
            selectionAnchor = target
            selectionExtensionEnd = target
        }
        return true
    }

    /// Activate the lone selected item: open the note, or navigate into the folder.
    /// No-op when the selection isn't a single item.
    @discardableResult
    func openSelectedItem() -> Bool {
        guard selection.count == 1, let item = selection.first else { return false }
        switch item {
        case let .note(id):
            if let note = notes.first(where: { $0.id == id }) {
                openNote(note)
                return true
            }
        case let .folder(path):
            if let folder = folders.first(where: { $0.name == path }) {
                navigateToFolder(folder)
                return true
            }
        }
        return false
    }

    // MARK: - Batch actions

    /// Move every note + folder in the current selection to the trash.
    /// Folders that are descendants of another selected folder are skipped
    /// because the parent's trash already swept them up.
    func trashSelection() {
        guard !selection.isEmpty else { return }
        let snapshot = selection
        let noteIDs: [UUID] = snapshot.compactMap {
            if case let .note(id) = $0 {
                id
            } else {
                nil
            }
        }
        let folderPaths: [String] = snapshot.compactMap {
            if case let .folder(path) = $0 {
                path
            } else {
                nil
            }
        }
        Log.storage.info("[NoteStore] trashSelection — \(noteIDs.count) notes, \(folderPaths.count) folders")
        for id in noteIDs {
            if let note = notes.first(where: { $0.id == id }) {
                trashNote(note)
            }
        }
        for path in folderPaths where folders.contains(where: { $0.name == path }) {
            trashFolder(path)
        }
        clearSelection()
    }

    /// Notes currently in the selection (resolved against the live note list).
    var selectedNotes: [Note] {
        selection.compactMap {
            if case let .note(id) = $0 {
                return notes.first(where: { $0.id == id })
            }
            return nil
        }
    }

    /// Folders currently in the selection.
    var selectedFolderPaths: [String] {
        selection.compactMap {
            if case let .folder(path) = $0 {
                path
            } else {
                nil
            }
        }
    }

    /// Move every selected note and folder into `targetFolder`.
    /// A target that is a selected folder itself or a descendant of a selected folder is skipped
    /// to avoid moving a folder into itself.
    func moveSelection(toFolder targetFolder: String) {
        guard !selection.isEmpty else { return }
        let noteSnapshot = selectedNotes
        let folderSnapshot = selectedFolderPaths
        let noteConflictsBefore = pendingNoteMoveConflicts.count
        let folderConflictsBefore = pendingFolderMoveConflicts.count
        for note in noteSnapshot {
            moveNote(note, to: targetFolder)
        }
        for path in folderSnapshot {
            // Skip moving a folder into itself or any of its own descendants.
            if targetFolder == path || targetFolder.hasPrefix(path + "/") {
                continue
            }
            moveFolder(path, toParent: targetFolder)
        }
        let queuedNotes = pendingNoteMoveConflicts.count - noteConflictsBefore
        let queuedFolders = pendingFolderMoveConflicts.count - folderConflictsBefore
        let movedNotes = noteSnapshot.count - queuedNotes
        let movedFolders = folderSnapshot.count - queuedFolders
        Log.storage.info("[NoteStore] moveSelection → '\(targetFolder, privacy: .public)' — moved \(movedNotes) notes + \(movedFolders) folders, queued \(queuedNotes + queuedFolders) conflicts")
        clearSelection()
    }

    /// Aggregate state of `tag` across the selected notes (for menu indicators).
    /// Returns `.on` when every selected note has it, `.off` when none do, `.mixed` otherwise.
    enum SelectionTagState { case on, off, mixed }
    func tagState(_ tag: TagColor) -> SelectionTagState {
        let notes = selectedNotes
        guard !notes.isEmpty else { return .off }
        let withTag = notes.count(where: { $0.tags.contains(tag) })
        if withTag == 0 {
            return .off
        }
        if withTag == notes.count {
            return .on
        }
        return .mixed
    }

    /// Finder/Mail-style batch tag toggle: if every selected note already has the tag,
    /// remove it from all of them; otherwise add the tag to every note that lacks it.
    func toggleTagOnSelection(_ tag: TagColor) {
        let notes = selectedNotes
        guard !notes.isEmpty else { return }
        let allHave = notes.allSatisfy { $0.tags.contains(tag) }
        Log.storage.info("[NoteStore] toggleTagOnSelection \(allHave ? "remove" : "add", privacy: .public) '\(tag.rawValue, privacy: .public)' on \(notes.count) notes")
        for note in notes {
            let has = note.tags.contains(tag)
            if allHave, has {
                toggleTag(tag, on: note)
            } else if !allHave, !has {
                toggleTag(tag, on: note)
            }
        }
    }

    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        dirtyNoteIDs.remove(note.id)
        do {
            try FileStorage.deleteNote(note)
        } catch {
            Log.storage.error("[NoteStore] deleteNote failed — \(error)")
        }
        refreshFolders()
    }

    func moveNote(_ note: Note, to folder: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let actualFilename = notes[index].savedFilename ?? notes[index].filename
        if noteFilenameWouldCollide(actualFilename, in: folder, excluding: note.id) {
            pendingNoteMoveConflicts.append(PendingNoteMoveConflict(noteID: note.id, targetFolder: folder))
            return
        }
        performMoveNote(at: index, to: folder)
    }

    func resolveNoteMoveConflict(keepBoth: Bool) {
        guard !pendingNoteMoveConflicts.isEmpty else { return }
        let conflict = pendingNoteMoveConflicts.removeFirst()
        guard let index = notes.firstIndex(where: { $0.id == conflict.noteID }) else { return }
        let folder = conflict.targetFolder
        let originalFilename = notes[index].savedFilename ?? notes[index].filename

        if keepBoth {
            // Find an unused title whose derived filename also doesn't collide on disk.
            let baseTitle = notes[index].title
            var counter = 2
            var newTitle = "\(baseTitle) \(counter)"
            var newFilename = "\(FileStorage.sanitizeForFilename(newTitle)).md"
            while noteFilenameWouldCollide(newFilename, in: folder, excluding: conflict.noteID) {
                counter += 1
                newTitle = "\(baseTitle) \(counter)"
                newFilename = "\(FileStorage.sanitizeForFilename(newTitle)).md"
            }
            notes[index].title = newTitle
            notes[index].modifiedAt = Date()
            // Rewrite the H1 heading line to match.
            var lines = notes[index].content.components(separatedBy: "\n")
            if let headingIdx = lines.firstIndex(where: { $0.hasPrefix("#") }) {
                let prefix = String(lines[headingIdx].prefix(while: { $0 == "#" }))
                lines[headingIdx] = "\(prefix) \(newTitle)"
                notes[index].content = lines.joined(separator: "\n")
            }
            // Atomic move + rename so the file actually lands at the new name on disk.
            performMoveNote(at: index, to: folder, renamingTo: newFilename)
            return
        }

        // Replace: trash the in-memory note whose effective filename matches at the destination.
        // If no in-memory note matches but a file is squatting on the destination path,
        // treat it as an orphan and remove it so the move can proceed.
        if let existing = notes.first(where: {
            $0.id != conflict.noteID
                && $0.folder == folder
                && (($0.savedFilename ?? $0.filename).caseInsensitiveCompare(originalFilename) == .orderedSame)
        }) {
            trashNote(existing)
        } else {
            let destURL = folder.isEmpty
                ? FileStorage.rootURL.appendingPathComponent(originalFilename)
                : FileStorage.rootURL.appendingPathComponent(folder).appendingPathComponent(originalFilename)
            if FileManager.default.fileExists(atPath: destURL.path) {
                do {
                    try FileManager.default.removeItem(at: destURL)
                    Log.storage.info("[NoteStore] resolveNoteMoveConflict Replace — removed orphan file at '\(destURL.path, privacy: .public)'")
                } catch {
                    Log.storage.error("[NoteStore] resolveNoteMoveConflict Replace — failed to remove orphan: \(error)")
                    return
                }
            }
        }

        if let idx = notes.firstIndex(where: { $0.id == conflict.noteID }) {
            performMoveNote(at: idx, to: folder)
        }
    }

    /// Drains the entire note conflict queue with one choice — backs the "Keep Both All" / "Replace All" buttons.
    func resolveAllNoteMoveConflicts(keepBoth: Bool) {
        var resolved = 0
        while !pendingNoteMoveConflicts.isEmpty {
            let before = pendingNoteMoveConflicts.count
            resolveNoteMoveConflict(keepBoth: keepBoth)
            if pendingNoteMoveConflicts.count >= before {
                break
            } // safety: ensure forward progress
            resolved += 1
        }
        Log.storage.info("[NoteStore] resolveAllNoteMoveConflicts \(keepBoth ? "keepBoth" : "replace", privacy: .public) — \(resolved) resolved")
    }

    /// Drops just the head note conflict — the next conflict (if any) becomes active.
    func skipNoteMoveConflict() {
        guard !pendingNoteMoveConflicts.isEmpty else { return }
        _ = pendingNoteMoveConflicts.removeFirst()
        let remaining = pendingNoteMoveConflicts.count
        Log.storage.info("[NoteStore] skipNoteMoveConflict — 1 note kept in original folder, \(remaining) remaining")
    }

    /// Discards every pending note conflict — items remain in their original folders.
    func cancelAllNoteMoveConflicts() {
        let count = pendingNoteMoveConflicts.count
        pendingNoteMoveConflicts.removeAll()
        if count > 0 {
            Log.storage.info("[NoteStore] cancelAllNoteMoveConflicts — \(count) notes kept in original folders")
        }
    }

    private func performMoveNote(at index: Int, to folder: String, renamingTo newFilename: String? = nil) {
        let note = notes[index]
        do {
            let movedSavedAt = try FileStorage.moveNote(note, toFolder: folder, withFilename: newFilename)
            notes[index].folder = folder
            notes[index].savedFilename = newFilename ?? note.savedFilename ?? note.filename
            notes[index].savedAt = movedSavedAt
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] moveNote failed — \(error)")
        }
    }

    // MARK: - Trash

    func trashNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].trashedAt = Date()
        dirtyNoteIDs.remove(note.id)

        // Move file to .trash/<UUID>_<Title>.md
        do {
            try FileStorage.trashNote(notes[index])
            let trashFilename = "\(notes[index].id.uuidString)_\(FileStorage.sanitizeForFilename(notes[index].title)).md"
            notes[index].savedFilename = trashFilename
        } catch {
            Log.storage.error("[NoteStore] trashNote failed — \(error)")
        }

        let trashedNote = notes.remove(at: index)
        trashedNotes.append(trashedNote)

        if selectedNote?.id == note.id {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNote = nil
            }
        }
        refreshFolders()
    }

    func trashFolder(_ name: String) {
        guard !name.isEmpty else { return }
        let prefix = name + "/"
        let now = Date()
        let folderID = UUID()

        // Collect notes in this folder and subfolders
        let folderNotes = notes.filter { $0.folder == name || $0.folder.hasPrefix(prefix) }

        // Move entire folder directory to .trash/
        do {
            try FileStorage.trashFolder(name, id: folderID, trashedAt: now)
        } catch {
            Log.storage.error("[NoteStore] trashFolder failed — \(error)")
            return
        }

        // Remove notes from active array
        notes.removeAll { $0.folder == name || $0.folder.hasPrefix(prefix) }

        let displayName = (name as NSString).lastPathComponent
        let savedDirname = "\(folderID.uuidString)_\(displayName)"
        trashedFolders.append(TrashedFolder(
            id: folderID,
            displayName: displayName,
            originalPath: name,
            trashedAt: now,
            notes: folderNotes,
            savedDirname: savedDirname,
        ))

        // Navigate away if inside this folder or any descendant
        if selectedFolder?.name == name || (selectedFolder?.name.hasPrefix(prefix) ?? false) {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolder = nil
            }
        }

        // Deselect note if it was in the trashed folder
        if let sel = selectedNote, sel.folder == name || sel.folder.hasPrefix(prefix) {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNote = nil
            }
        }

        // Remove trashed folder and all sub-paths from cache
        let oldPrefix = name + "/"
        diskFolderNames = diskFolderNames.filter { $0 != name && !$0.hasPrefix(oldPrefix) }
        refreshFolders()
    }

    func restoreNote(_ note: Note) {
        guard let index = trashedNotes.firstIndex(where: { $0.id == note.id }) else { return }
        trashedNotes[index].trashedAt = nil

        // Move file from .trash/ back to original folder
        do {
            let result = try FileStorage.restoreNote(trashedNotes[index])
            trashedNotes[index].savedFilename = result.filename
            trashedNotes[index].savedAt = result.savedAt
        } catch {
            Log.storage.error("[NoteStore] restoreNote failed — \(error)")
        }

        let restoredNote = trashedNotes.remove(at: index)
        notes.append(restoredNote)
        refreshFolders()
    }

    func restoreFolder(_ folder: TrashedFolder) {
        do {
            try FileStorage.restoreFolder(folder)
        } catch {
            Log.storage.error("[NoteStore] restoreFolder failed — \(error)")
            return
        }

        // Sync savedAt from the sidecar — restoreFolder wrote the actual post-move
        // file mtimes there, so in-memory notes match what checkForExternalChanges sees.
        var restoredNotes = folder.notes
        for i in restoredNotes.indices {
            if let entry = SidecarStore.shared.noteEntry(for: restoredNotes[i].id) {
                restoredNotes[i].savedAt = entry.savedAt
            }
        }
        notes.append(contentsOf: restoredNotes)
        trashedFolders.removeAll { $0.id == folder.id }
        refreshFolders()
    }

    func permanentlyDeleteNote(_ note: Note) {
        trashedNotes.removeAll { $0.id == note.id }
        do {
            try FileStorage.deleteTrashedNote(note)
        } catch {
            Log.storage.error("[NoteStore] permanentlyDeleteNote failed — \(error)")
        }
    }

    func permanentlyDeleteFolder(_ folder: TrashedFolder) {
        trashedFolders.removeAll { $0.id == folder.id }
        do {
            try FileStorage.deleteTrashedFolder(folder)
        } catch {
            Log.storage.error("[NoteStore] permanentlyDeleteFolder failed — \(error)")
        }
        // Folder color metadata persists under the original path while in trash so
        // restore preserves it. Permanent delete is the right place to clean it up.
        SidecarStore.shared.removeFolderSubtree(path: folder.originalPath)
        try? SidecarStore.shared.save()
    }

    func emptyTrash() {
        for note in trashedNotes {
            do {
                try FileStorage.deleteTrashedNote(note)
            } catch {
                Log.storage.error("[NoteStore] emptyTrash note failed — \(error)")
            }
        }
        trashedNotes.removeAll()

        for folder in trashedFolders {
            do {
                try FileStorage.deleteTrashedFolder(folder)
            } catch {
                Log.storage.error("[NoteStore] emptyTrash folder failed — \(error)")
            }
        }
        trashedFolders.removeAll()
    }

    /// Total number of items in trash (notes + folders).
    var trashItemCount: Int {
        trashedNotes.count + trashedFolders.count
    }

    /// Whether trash is empty (no notes and no folders).
    var isTrashEmpty: Bool {
        trashedNotes.isEmpty && trashedFolders.isEmpty
    }

    /// Permanently delete notes/folders that have been in trash for more than 60 days.
    private func autoPurgeExpiredTrash() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let expiredNotes = trashedNotes.filter { ($0.trashedAt ?? Date()) < cutoff }
        for note in expiredNotes {
            permanentlyDeleteNote(note)
        }
        let expiredFolders = trashedFolders.filter { $0.trashedAt < cutoff }
        for folder in expiredFolders {
            permanentlyDeleteFolder(folder)
        }
        let purgedCount = expiredNotes.count + expiredFolders.count
        if purgedCount > 0 {
            Log.storage.info("[NoteStore] auto-purged \(purgedCount) expired trash items")
        }
    }

    // MARK: - Folder CRUD

    func createFolder(named name: String, in parent: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fullPath = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"
        do {
            try FileStorage.ensureFolderExists(fullPath)
            diskFolderNames.insert(fullPath)
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] createFolder failed — \(error)")
        }
    }

    func renameFolder(_ oldName: String, to newName: String) {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !trimmedNew.isEmpty, oldName != trimmedNew else { return }
        // Build new full path: replace last component only
        let parent = (oldName as NSString).deletingLastPathComponent
        let parentPath = parent == "." ? "" : parent
        let newFullPath = parentPath.isEmpty ? trimmedNew : "\(parentPath)/\(trimmedNew)"
        guard !folders.contains(where: { $0.name == newFullPath }) else { return }

        do {
            try FileStorage.renameFolder(oldName, to: newFullPath)
            // Update notes in this folder AND all subfolders
            let oldPrefix = oldName + "/"
            for i in notes.indices {
                if notes[i].folder == oldName {
                    notes[i].folder = newFullPath
                } else if notes[i].folder.hasPrefix(oldPrefix) {
                    notes[i].folder = newFullPath + String(notes[i].folder.dropFirst(oldName.count))
                }
            }
            if selectedFolder?.name == oldName {
                selectedFolder = Folder(name: newFullPath, noteCount: selectedFolder?.noteCount ?? 0)
            }
            // Update cache: rename oldName and all sub-paths (reuses oldPrefix declared above)
            diskFolderNames = Set(diskFolderNames.map { path in
                if path == oldName {
                    return newFullPath
                }
                if path.hasPrefix(oldPrefix) {
                    return newFullPath + path.dropFirst(oldName.count)
                }
                return path
            })
            updateSidecarPaths(for: notes)
            SidecarStore.shared.renameFolderEntries(from: oldName, to: newFullPath)
            try? SidecarStore.shared.save()
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] renameFolder failed — \(error)")
        }
    }

    func moveFolder(_ name: String, toParent newParent: String) {
        guard !name.isEmpty else { return }
        let displayName = (name as NSString).lastPathComponent
        let newFullPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"
        guard newFullPath != name else { return }
        guard !newParent.hasPrefix(name + "/"), newParent != name else { return }

        if folderWouldCollide(displayName: displayName, in: newParent, excluding: name) {
            pendingFolderMoveConflicts.append(PendingFolderMoveConflict(folderName: name, targetParent: newParent))
            return
        }
        performMoveFolder(name, toParent: newParent)
    }

    func resolveFolderMoveConflict(keepBoth: Bool) {
        guard !pendingFolderMoveConflicts.isEmpty else { return }
        let conflict = pendingFolderMoveConflicts.removeFirst()
        let name = conflict.folderName
        let newParent = conflict.targetParent
        let displayName = (name as NSString).lastPathComponent
        let targetFullPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"

        if keepBoth {
            // Loop on filesystem-aware check so we don't pick a name an orphan dir already squats on.
            var counter = 2
            var newDisplayName = "\(displayName) \(counter)"
            while folderWouldCollide(displayName: newDisplayName, in: newParent) {
                counter += 1
                newDisplayName = "\(displayName) \(counter)"
            }
            // Rename locally first, then move
            renameFolder(name, to: newDisplayName)
            let renamedPath = (name as NSString).deletingLastPathComponent
            let renamedParent = renamedPath == "." ? "" : renamedPath
            let renamedFullPath = renamedParent.isEmpty ? newDisplayName : "\(renamedParent)/\(newDisplayName)"
            performMoveFolder(renamedFullPath, toParent: newParent)
            return
        }

        // Replace: trash the existing tracked folder at destination, OR remove an orphan dir on disk.
        if let existingFolder = folders.first(where: { $0.name == targetFullPath }) {
            trashFolder(existingFolder.name)
        } else {
            let destURL = newParent.isEmpty
                ? FileStorage.rootURL.appendingPathComponent(displayName)
                : FileStorage.rootURL.appendingPathComponent(newParent).appendingPathComponent(displayName)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: destURL.path, isDirectory: &isDir), isDir.boolValue {
                do {
                    try FileManager.default.removeItem(at: destURL)
                    Log.storage.info("[NoteStore] resolveFolderMoveConflict Replace — removed orphan directory at '\(destURL.path, privacy: .public)'")
                } catch {
                    Log.storage.error("[NoteStore] resolveFolderMoveConflict Replace — failed to remove orphan directory: \(error)")
                    return
                }
            }
        }
        performMoveFolder(name, toParent: newParent)
    }

    /// Drains the entire folder conflict queue with one choice — backs the "Keep Both All" / "Replace All" buttons.
    func resolveAllFolderMoveConflicts(keepBoth: Bool) {
        var resolved = 0
        while !pendingFolderMoveConflicts.isEmpty {
            let before = pendingFolderMoveConflicts.count
            resolveFolderMoveConflict(keepBoth: keepBoth)
            if pendingFolderMoveConflicts.count >= before {
                break
            }
            resolved += 1
        }
        Log.storage.info("[NoteStore] resolveAllFolderMoveConflicts \(keepBoth ? "keepBoth" : "replace", privacy: .public) — \(resolved) resolved")
    }

    /// Drops just the head folder conflict.
    func skipFolderMoveConflict() {
        guard !pendingFolderMoveConflicts.isEmpty else { return }
        _ = pendingFolderMoveConflicts.removeFirst()
        let remaining = pendingFolderMoveConflicts.count
        Log.storage.info("[NoteStore] skipFolderMoveConflict — 1 folder kept in original parent, \(remaining) remaining")
    }

    /// Discards every pending folder conflict.
    func cancelAllFolderMoveConflicts() {
        let count = pendingFolderMoveConflicts.count
        pendingFolderMoveConflicts.removeAll()
        if count > 0 {
            Log.storage.info("[NoteStore] cancelAllFolderMoveConflicts — \(count) folders kept in original parents")
        }
    }

    private func performMoveFolder(_ name: String, toParent newParent: String) {
        let displayName = (name as NSString).lastPathComponent
        let newFullPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"

        do {
            try FileStorage.moveFolder(name, toParent: newParent)
            let oldPrefix = name + "/"
            for i in notes.indices {
                if notes[i].folder == name {
                    notes[i].folder = newFullPath
                } else if notes[i].folder.hasPrefix(oldPrefix) {
                    notes[i].folder = newFullPath + "/" + String(notes[i].folder.dropFirst(oldPrefix.count))
                }
            }
            if selectedFolder?.name == name {
                selectedFolder = Folder(name: newFullPath, noteCount: selectedFolder?.noteCount ?? 0)
            }
            // Update cache: rename moved folder and all sub-paths (reuses oldPrefix declared above)
            diskFolderNames = Set(diskFolderNames.map { path in
                if path == name {
                    return newFullPath
                }
                if path.hasPrefix(oldPrefix) {
                    return newFullPath + "/" + path.dropFirst(oldPrefix.count)
                }
                return path
            })
            updateSidecarPaths(for: notes)
            SidecarStore.shared.renameFolderEntries(from: name, to: newFullPath)
            try? SidecarStore.shared.save()
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] moveFolder failed — \(error)")
        }
    }

    /// Folders that are direct children of the given parent path.
    func childFolders(of parent: String) -> [Folder] {
        folders.filter { $0.parentPath == parent }
    }

    /// All notes in a folder (and its subfolders), sorted by most recently
    /// modified. Used by the hover-peek preview to show the folder's contents.
    func recentNotes(in folder: Folder) -> [Note] {
        let prefix = folder.name + "/"
        let folderNotes = notes.filter { $0.folder == folder.name || $0.folder.hasPrefix(prefix) }
        return folderNotes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Immediate child folders of the given folder. Used by the hover-peek
    /// preview to show the folder hierarchy.
    func subfolders(of folder: Folder) -> [Folder] {
        let prefix = folder.name + "/"
        return folders.filter { child in
            child.name.hasPrefix(prefix) && !child.name.dropFirst(prefix.count).contains("/")
        }
    }

    /// Set or clear the color of a folder. Persisted in the sidecar; UI refresh follows.
    func setFolderColor(_ color: TagColor?, for folderName: String) {
        guard !folderName.isEmpty else { return }
        if let color {
            SidecarStore.shared.upsertFolder(
                SidecarStore.FolderEntry(color: color.rawValue),
                forPath: folderName,
            )
        } else {
            SidecarStore.shared.removeFolder(path: folderName)
        }
        try? SidecarStore.shared.save()
        refreshFolders()
    }

    // MARK: - Save

    func saveDirtyNotes() {
        if !dirtyNoteIDs.isEmpty {
            let count = dirtyNoteIDs.count
            Log.storage.debug("[NoteStore] saving \(count) dirty notes")
        }
        for noteID in dirtyNoteIDs {
            guard let index = notes.firstIndex(where: { $0.id == noteID }) else { continue }
            do {
                let result = try FileStorage.writeNote(notes[index])
                notes[index].savedFilename = result.filename
                notes[index].savedAt = result.savedAt
                if let updated = result.updatedContent {
                    notes[index].content = updated
                    if selectedNote?.id == noteID {
                        selectedNote?.content = updated
                        let noteTitle = notes[index].title
                        Log.storage.info("[Image] reloading editor after image path rewrite for '\(noteTitle, privacy: .public)'")
                        onNeedEditorReload?(updated)
                    }
                }
                if selectedNote?.id == noteID {
                    selectedNote?.savedFilename = result.filename
                    selectedNote?.savedAt = result.savedAt
                }
                // Clean up orphaned images (deleted from body but file still on disk)
                FileStorage.cleanOrphanedImages(forNote: notes[index], body: notes[index].content)
            } catch {
                Log.storage.error("[NoteStore] saveDirtyNotes failed for \(noteID) — \(error)")
            }
        }
        dirtyNoteIDs.removeAll()
    }

    // MARK: - Private

    private func refreshFolders() {
        let folderNames = Set(notes.map(\.folder)).filter { !$0.isEmpty }
        let allNames = folderNames.union(diskFolderNames).sorted()

        folders = allNames.map { name in
            let prefix = name + "/"
            // Count notes in this folder AND all subfolders (recursive)
            let descendantNotes = notes.filter { $0.folder == name || $0.folder.hasPrefix(prefix) }
            let color = SidecarStore.shared.folderEntry(forPath: name)
                .flatMap { TagColor(rawValue: $0.color) }
            return Folder(
                name: name,
                noteCount: descendantNotes.count,
                latestModifiedAt: descendantNotes.map(\.modifiedAt).max(),
                earliestCreatedAt: descendantNotes.map(\.createdAt).min(),
                color: color,
            )
        }
        // Folder/note membership changed → tag set may have too.
        recomputeAllUsedTags()
    }

    /// Sync sidecar NoteEntry.path for all notes whose current in-memory path
    /// differs from what is stored. Called after folder rename/move.
    private func updateSidecarPaths(for notes: [Note]) {
        var changed = false
        for note in notes {
            let actualFilename = note.savedFilename ?? note.filename
            let expectedPath = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
            if var entry = SidecarStore.shared.noteEntry(for: note.id), entry.path != expectedPath {
                entry.path = expectedPath
                SidecarStore.shared.upsertNote(entry, for: note.id)
                changed = true
            }
        }
        if changed {
            try? SidecarStore.shared.save()
        }
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
