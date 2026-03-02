import Cocoa
import SwiftUI

struct TrashView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(L10n.self) var l10n

    @State private var deletingNote: Note?
    @State private var deletingFolder: TrashedFolder?
    @State private var showDeleteNoteConfirm = false
    @State private var showDeleteFolderConfirm = false
    @State private var showEmptyTrashConfirm = false
    @State private var selectedTrashedFolder: TrashedFolder?
    @State private var previewingNote: Note?
    /// Current browse path within the selected trashed folder.
    @State private var browsePath: String?
    /// Direction for internal trash navigation transitions.
    @State private var internalDirection: NoteStore.NavigationDirection = .none

    private let iconWidth: CGFloat = 22

    /// Internal transition based on navigation direction within trash.
    private var internalTransition: AnyTransition {
        switch internalDirection {
        case .forward:
            .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading),
            )
        case .backward:
            .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing),
            )
        default:
            .opacity
        }
    }

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
        ZStack {
            if previewingNote != nil {
                notePreview
                    .transition(internalTransition)
            } else if let folder = selectedTrashedFolder {
                if noteStore.trashedFolders.contains(where: { $0.id == folder.id }) {
                    trashedFolderDetail(folder: folder)
                        .id(browsePath)
                        .transition(internalTransition)
                } else {
                    trashList
                        .transition(internalTransition)
                        .onAppear {
                            selectedTrashedFolder = nil
                            browsePath = nil
                        }
                }
            } else {
                trashList
                    .transition(internalTransition)
            }
        }
        .clipped()
    }

    // MARK: - Trash List

    private var trashList: some View {
        PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: l10n["common.back"],
                ) {
                    noteStore.closeTrash()
                }

                Spacer()

                HeaderIconButton(
                    systemName: "trash.slash",
                    help: l10n["trash.emptyTrash"],
                ) {
                    showEmptyTrashConfirm = true
                }
                .opacity(noteStore.isTrashEmpty ? 0.3 : 1)
                .disabled(noteStore.isTrashEmpty)
            }
            .overlay {
                Text(l10n["trash.title"])
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
        .alert(l10n["alert.emptyTrash.title"], isPresented: $showEmptyTrashConfirm) {
            Button(l10n["trash.emptyTrash"], role: .destructive) {
                noteStore.emptyTrash()
            }
            Button(l10n["common.cancel"], role: .cancel) {}
        } message: {
            let count = noteStore.trashItemCount
            Text(l10n.t("alert.emptyTrash.message", "\(count)"))
        }
        .alert(l10n["alert.deletePermanent.note.title"], isPresented: $showDeleteNoteConfirm) {
            Button(l10n["common.delete"], role: .destructive) {
                if let note = deletingNote {
                    noteStore.permanentlyDeleteNote(note)
                    deletingNote = nil
                }
            }
            Button(l10n["common.cancel"], role: .cancel) {
                deletingNote = nil
            }
        } message: {
            if let note = deletingNote {
                Text(l10n.t("alert.deletePermanent.note.message", note.title))
            }
        }
        .alert(l10n["alert.deletePermanent.folder.title"], isPresented: $showDeleteFolderConfirm) {
            Button(l10n["common.delete"], role: .destructive) {
                if let folder = deletingFolder {
                    noteStore.permanentlyDeleteFolder(folder)
                    deletingFolder = nil
                    if selectedTrashedFolder?.id == folder.id {
                        closeTrashedFolder()
                    }
                }
            }
            Button(l10n["common.cancel"], role: .cancel) {
                deletingFolder = nil
            }
        } message: {
            if let folder = deletingFolder {
                let noteCount = folder.notes.count
                Text(l10n.t("alert.deletePermanent.folder.message", folder.displayName, "\(noteCount)"))
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
                            help: l10n["common.back"],
                        ) {
                            closeNotePreview()
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(note.title.isEmpty ? l10n["common.untitled"] : note.title)
                                .font(.headline)
                                .lineLimit(1)

                            Text(l10n["editor.readOnly"])
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if isPreviewingIndividualNote {
                            HeaderIconButton(
                                systemName: "arrow.uturn.backward",
                                help: l10n["editor.restoreNote"],
                            ) {
                                noteStore.restoreNote(note)
                                closeNotePreview()
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
                    help: l10n["common.back"],
                ) {
                    navigateBackInFolder(folder: folder)
                }

                Spacer()

                HeaderIconButton(
                    systemName: "arrow.uturn.backward",
                    help: l10n["trash.restoreFolder"],
                ) {
                    noteStore.restoreFolder(folder)
                    closeTrashedFolder()
                }

                HeaderIconButton(
                    systemName: "trash",
                    help: l10n["common.deletePermanently"],
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
                        title: l10n["trash.emptyFolder.title"],
                        subtitle: l10n["trash.emptyFolder.subtitle"],
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
                                    internalDirection = .forward
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        browsePath = currentPath + "/" + subfolder.name
                                    }
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
                                    openNotePreview(note)
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
        .alert(l10n["alert.deletePermanent.folder.title"], isPresented: $showDeleteFolderConfirm) {
            Button(l10n["common.delete"], role: .destructive) {
                if let folder = deletingFolder {
                    noteStore.permanentlyDeleteFolder(folder)
                    deletingFolder = nil
                    closeTrashedFolder()
                }
            }
            Button(l10n["common.cancel"], role: .cancel) {
                deletingFolder = nil
            }
        } message: {
            if let folder = deletingFolder {
                let noteCount = folder.notes.count
                Text(l10n.t("alert.deletePermanent.folder.message", folder.displayName, "\(noteCount)"))
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
            closeTrashedFolder()
        } else {
            internalDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                browsePath = (currentPath as NSString).deletingLastPathComponent
            }
        }
    }

    // MARK: - Row Builders

    private func trashedNoteRow(note: Note) -> some View {
        TrashedNoteRowView(note: note, iconWidth: iconWidth) {
            openNotePreview(note)
        }
        .contextMenu {
            Button(l10n["common.restore"]) {
                noteStore.restoreNote(note)
            }

            Divider()

            Button(l10n["common.deletePermanently"], role: .destructive) {
                deletingNote = note
                showDeleteNoteConfirm = true
            }
        }
    }

    private func trashedFolderRow(folder: TrashedFolder) -> some View {
        TrashedFolderRowView(folder: folder, iconWidth: iconWidth) {
            openTrashedFolder(folder)
        }
        .contextMenu {
            Button(l10n["common.open"]) {
                openTrashedFolder(folder)
            }

            Button(l10n["common.restore"]) {
                noteStore.restoreFolder(folder)
            }

            Divider()

            Button(l10n["common.deletePermanently"], role: .destructive) {
                deletingFolder = folder
                showDeleteFolderConfirm = true
            }
        }
    }

    // MARK: - Internal Navigation Helpers

    private func openTrashedFolder(_ folder: TrashedFolder) {
        internalDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTrashedFolder = folder
            browsePath = folder.originalPath
        }
    }

    private func closeTrashedFolder() {
        internalDirection = .backward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTrashedFolder = nil
            browsePath = nil
        }
    }

    private func openNotePreview(_ note: Note) {
        internalDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            previewingNote = note
        }
    }

    private func closeNotePreview() {
        internalDirection = .backward
        withAnimation(.easeInOut(duration: 0.2)) {
            previewingNote = nil
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "trash",
            title: l10n["trash.empty.title"],
            subtitle: l10n["trash.empty.subtitle"],
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
        let l10n = L10n.shared
        guard let trashedAt = note.trashedAt else { return "" }
        let days = Calendar.current.dateComponents([.day], from: trashedAt, to: Date()).day ?? 0
        let remaining = max(60 - days, 0)
        let folder = note.folder.isEmpty ? l10n["common.root"] : note.folder
        let trashedText = days == 0 ? l10n["trash.trashedToday"] : l10n.t("trash.trashedAgo", "\(days)")
        let daysLeft = l10n.t("trash.daysLeft", "\(remaining)")
        return "\(folder) \u{00B7} \(trashedText) \u{00B7} \(daysLeft)"
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
                        Text(note.title.isEmpty ? L10n.shared["common.untitled"] : note.title)
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
        let l10n = L10n.shared
        let days = Calendar.current.dateComponents([.day], from: folder.trashedAt, to: Date()).day ?? 0
        let remaining = max(60 - days, 0)
        let parent = (folder.originalPath as NSString).deletingLastPathComponent
        let parentDisplay = parent.isEmpty || parent == "." ? "" : l10n.t("trash.from", parent) + " \u{00B7} "
        let trashedText = days == 0 ? l10n["trash.trashedToday"] : l10n.t("trash.trashedAgo", "\(days)")
        let daysLeft = l10n.t("trash.daysLeft", "\(remaining)")
        return "\(parentDisplay)\(trashedText) \u{00B7} \(daysLeft)"
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
