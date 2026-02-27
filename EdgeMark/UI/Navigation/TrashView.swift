import Cocoa
import SwiftUI

struct TrashView: View {
    @Environment(NoteStore.self) var noteStore

    @State private var deletingNote: Note?
    @State private var deletingFolder: TrashedFolder?
    @State private var showDeleteNoteConfirm = false
    @State private var showDeleteFolderConfirm = false
    @State private var showEmptyTrashConfirm = false
    @State private var selectedTrashedFolder: TrashedFolder?
    @State private var previewingNote: Note?
    /// Current browse path within the selected trashed folder.
    @State private var browsePath: String?

    private let iconWidth: CGFloat = 22

    /// Unified trash item for sorting notes and folders together by trashedAt.
    private enum TrashItem: Identifiable {
        case note(Note)
        case folder(TrashedFolder)

        var id: UUID {
            switch self {
            case let .note(n): n.id
            case let .folder(f): f.id
            }
        }

        var trashedAt: Date {
            switch self {
            case let .note(n): n.trashedAt ?? .distantPast
            case let .folder(f): f.trashedAt
            }
        }
    }

    private var sortedTrashItems: [TrashItem] {
        let noteItems = noteStore.trashedNotes.map { TrashItem.note($0) }
        let folderItems = noteStore.trashedFolders.map { TrashItem.folder($0) }
        return (noteItems + folderItems).sorted { $0.trashedAt > $1.trashedAt }
    }

    /// Whether the previewing note is individually trashed (vs part of a trashed folder).
    private var isPreviewingIndividualNote: Bool {
        guard let note = previewingNote else { return false }
        return noteStore.trashedNotes.contains(where: { $0.id == note.id })
    }

    var body: some View {
        if previewingNote != nil {
            notePreview
        } else if let folder = selectedTrashedFolder {
            if noteStore.trashedFolders.contains(where: { $0.id == folder.id }) {
                trashedFolderDetail(folder: folder)
            } else {
                trashList
                    .onAppear {
                        selectedTrashedFolder = nil
                        browsePath = nil
                    }
            }
        } else {
            trashList
        }
    }

    // MARK: - Trash List

    private var trashList: some View {
        PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: "Back",
                ) {
                    noteStore.showTrash = false
                }

                Spacer()

                HeaderIconButton(
                    systemName: "trash.slash",
                    help: "Empty Trash",
                ) {
                    showEmptyTrashConfirm = true
                }
                .opacity(noteStore.isTrashEmpty ? 0.3 : 1)
                .disabled(noteStore.isTrashEmpty)
            }
            .overlay {
                Text("Trash")
                    .font(.headline)
            }
        } content: {
            VStack(spacing: 0) {
                ZStack {
                    emptyState
                        .opacity(noteStore.isTrashEmpty ? 1 : 0)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sortedTrashItems) { item in
                                switch item {
                                case let .note(note):
                                    trashedNoteRow(note: note)
                                case let .folder(folder):
                                    trashedFolderRow(folder: folder)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .opacity(noteStore.isTrashEmpty ? 0 : 1)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
            }
        }
        .alert("Empty Trash?", isPresented: $showEmptyTrashConfirm) {
            Button("Empty Trash", role: .destructive) {
                noteStore.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = noteStore.trashItemCount
            Text("All \(count) item(s) will be permanently deleted. This cannot be undone.")
        }
        .alert("Delete Permanently?", isPresented: $showDeleteNoteConfirm) {
            Button("Delete", role: .destructive) {
                if let note = deletingNote {
                    noteStore.permanentlyDeleteNote(note)
                    deletingNote = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deletingNote = nil
            }
        } message: {
            if let note = deletingNote {
                Text("\u{201C}\(note.title)\u{201D} will be permanently deleted. This cannot be undone.")
            }
        }
        .alert("Delete Folder Permanently?", isPresented: $showDeleteFolderConfirm) {
            Button("Delete", role: .destructive) {
                if let folder = deletingFolder {
                    noteStore.permanentlyDeleteFolder(folder)
                    deletingFolder = nil
                    if selectedTrashedFolder?.id == folder.id {
                        selectedTrashedFolder = nil
                        browsePath = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                deletingFolder = nil
            }
        } message: {
            if let folder = deletingFolder {
                let noteCount = folder.notes.count
                Text(
                    "\u{201C}\(folder.displayName)\u{201D} and its \(noteCount) note(s) will be permanently deleted. This cannot be undone.",
                )
            }
        }
    }

    // MARK: - Note Preview

    private var notePreview: some View {
        PageLayout {
            if let note = previewingNote {
                VStack(spacing: 4) {
                    HStack {
                        HeaderIconButton(
                            systemName: "chevron.left",
                            help: "Back",
                        ) {
                            previewingNote = nil
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.headline)
                                .lineLimit(1)

                            Text("(read-only)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if isPreviewingIndividualNote {
                            HeaderIconButton(
                                systemName: "arrow.uturn.backward",
                                help: "Restore Note",
                            ) {
                                noteStore.restoreNote(note)
                                previewingNote = nil
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text(note.modifiedAt.homeDisplayFormat)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                            Text(note.createdAt.homeDisplayFormat)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        } content: {
            if let note = previewingNote {
                ReadOnlyMarkdownView(content: note.content)
            }
        }
    }

    // MARK: - Trashed Folder Detail

    /// Lightweight struct for subfolder display within a trashed folder.
    private struct SubfolderInfo: Identifiable {
        var id: String {
            name
        }

        let name: String
        let noteCount: Int
        let latestModifiedAt: Date?
    }

    private func trashedFolderDetail(folder: TrashedFolder) -> some View {
        let currentPath = browsePath ?? folder.originalPath
        let folderDisplayName = (currentPath as NSString).lastPathComponent
        let folderDisplayPath: String = {
            let relative = currentPath == folder.originalPath
                ? folder.displayName
                : "\(folder.displayName)/\(String(currentPath.dropFirst(folder.originalPath.count + 1)))"
            return "/.trash/\(relative)/"
        }()

        let childSubfolders = computeChildSubfolders(at: currentPath, in: folder.notes)
        let directNotes = folder.notes.filter { $0.folder == currentPath }
        let isEmpty = childSubfolders.isEmpty && directNotes.isEmpty

        return PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: "Back",
                ) {
                    navigateBackInFolder(folder: folder)
                }

                Spacer()

                HeaderIconButton(
                    systemName: "arrow.uturn.backward",
                    help: "Restore Folder",
                ) {
                    noteStore.restoreFolder(folder)
                    selectedTrashedFolder = nil
                    browsePath = nil
                }

                HeaderIconButton(
                    systemName: "trash",
                    help: "Delete Permanently",
                ) {
                    deletingFolder = folder
                    showDeleteFolderConfirm = true
                }
            }
            .overlay {
                HStack(spacing: 4) {
                    Text(folderDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Text(folderDisplayPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, 40)
                .padding(.trailing, 75)
                .help(folderDisplayPath)
            }
        } content: {
            VStack(spacing: 0) {
                ZStack {
                    EmptyStateView(
                        icon: "folder",
                        title: "Empty Folder",
                        subtitle: "This folder has no notes",
                    )
                    .opacity(isEmpty ? 1 : 0)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(childSubfolders) { subfolder in
                                FolderRowView(
                                    name: subfolder.name,
                                    count: subfolder.noteCount,
                                    date: subfolder.latestModifiedAt,
                                    iconWidth: iconWidth,
                                ) {
                                    browsePath = currentPath + "/" + subfolder.name
                                }
                            }

                            if !childSubfolders.isEmpty, !directNotes.isEmpty {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                            }

                            ForEach(directNotes) { note in
                                NoteRowView(
                                    note: note,
                                    iconWidth: iconWidth,
                                ) {
                                    previewingNote = note
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .opacity(isEmpty ? 0 : 1)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
            }
        }
        .alert("Delete Folder Permanently?", isPresented: $showDeleteFolderConfirm) {
            Button("Delete", role: .destructive) {
                if let folder = deletingFolder {
                    noteStore.permanentlyDeleteFolder(folder)
                    deletingFolder = nil
                    selectedTrashedFolder = nil
                    browsePath = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deletingFolder = nil
            }
        } message: {
            if let folder = deletingFolder {
                let noteCount = folder.notes.count
                Text(
                    "\u{201C}\(folder.displayName)\u{201D} and its \(noteCount) note(s) will be permanently deleted. This cannot be undone.",
                )
            }
        }
    }

    /// Derive child subfolder info at the given path from the notes array.
    private func computeChildSubfolders(at path: String, in notes: [Note]) -> [SubfolderInfo] {
        let prefix = path + "/"
        var childMap: [String: [Note]] = [:]
        for note in notes {
            guard note.folder.hasPrefix(prefix) else { continue }
            let remainder = String(note.folder.dropFirst(prefix.count))
            guard let firstComponent = remainder.split(separator: "/").first.map(String.init),
                  !firstComponent.isEmpty
            else { continue }
            childMap[firstComponent, default: []].append(note)
        }

        return childMap.map { name, childNotes in
            SubfolderInfo(
                name: name,
                noteCount: childNotes.count,
                latestModifiedAt: childNotes.map(\.modifiedAt).max(),
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func navigateBackInFolder(folder: TrashedFolder) {
        let currentPath = browsePath ?? folder.originalPath
        if currentPath == folder.originalPath {
            selectedTrashedFolder = nil
            browsePath = nil
        } else {
            browsePath = (currentPath as NSString).deletingLastPathComponent
        }
    }

    // MARK: - Row Builders

    private func trashedNoteRow(note: Note) -> some View {
        TrashedNoteRowView(note: note, iconWidth: iconWidth) {
            previewingNote = note
        }
        .contextMenu {
            Button("Restore") {
                noteStore.restoreNote(note)
            }

            Divider()

            Button("Delete Permanently", role: .destructive) {
                deletingNote = note
                showDeleteNoteConfirm = true
            }
        }
    }

    private func trashedFolderRow(folder: TrashedFolder) -> some View {
        TrashedFolderRowView(folder: folder, iconWidth: iconWidth) {
            selectedTrashedFolder = folder
            browsePath = folder.originalPath
        }
        .contextMenu {
            Button("Open") {
                selectedTrashedFolder = folder
                browsePath = folder.originalPath
            }

            Button("Restore") {
                noteStore.restoreFolder(folder)
            }

            Divider()

            Button("Delete Permanently", role: .destructive) {
                deletingFolder = folder
                showDeleteFolderConfirm = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "trash",
            title: "Trash is Empty",
            subtitle: "Deleted items appear here for 60 days",
        )
    }
}

// MARK: - Trashed Note Row View

/// Matches NoteRowView layout: title + date on right, trash info as subtitle.
private struct TrashedNoteRowView: View {
    let note: Note
    let iconWidth: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false

    private var trashInfo: String {
        guard let trashedAt = note.trashedAt else { return "" }
        let days = Calendar.current.dateComponents([.day], from: trashedAt, to: Date()).day ?? 0
        let remaining = max(60 - days, 0)
        let folder = note.folder.isEmpty ? "Root" : note.folder
        if days == 0 {
            return "\(folder) \u{00B7} Trashed today \u{00B7} \(remaining)d left"
        }
        return "\(folder) \u{00B7} Trashed \(days)d ago \u{00B7} \(remaining)d left"
    }

    var body: some View {
        Button {
            onTap()
        } label: {
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

                    Text(trashInfo)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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

// MARK: - Trashed Folder Row View

/// Matches FolderRowView layout: folder.fill icon with count badge, name + date, trash info subtitle.
private struct TrashedFolderRowView: View {
    let folder: TrashedFolder
    let iconWidth: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false

    private var trashInfo: String {
        let days = Calendar.current.dateComponents([.day], from: folder.trashedAt, to: Date()).day ?? 0
        let remaining = max(60 - days, 0)
        let parent = (folder.originalPath as NSString).deletingLastPathComponent
        let parentDisplay = parent.isEmpty || parent == "." ? "" : "from \(parent)/ \u{00B7} "
        if days == 0 {
            return "\(parentDisplay)Trashed today \u{00B7} \(remaining)d left"
        }
        return "\(parentDisplay)Trashed \(days)d ago \u{00B7} \(remaining)d left"
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)

                    if !folder.notes.isEmpty {
                        Text("\(folder.notes.count)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.background)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(.primary.opacity(0.8), in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
                .frame(width: iconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(folder.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Text(folder.trashedAt.homeDisplayFormat)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(trashInfo)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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
