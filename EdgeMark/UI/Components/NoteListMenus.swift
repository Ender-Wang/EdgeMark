import Cocoa
import SwiftUI

/// Shared menu builders for note and folder context menus and move-to submenus.
enum NoteListMenus {
    // MARK: - Context Menu Items

    /// Context menu items for a note row.
    @ViewBuilder
    static func noteContextMenuItems(
        note: Note,
        noteStore: NoteStore,
        l10n: L10n,
        onRename: @escaping () -> Void,
    ) -> some View {
        Button(l10n["common.rename"], action: onRename)

        noteMoveMenu(for: note, noteStore: noteStore, l10n: l10n)

        Divider()

        Button(l10n["common.copyPlainText"]) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.plainText, forType: .string)
        }

        Button(l10n["common.copyMarkdown"]) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.content, forType: .string)
        }

        Divider()

        Button(l10n["common.showInFinder"]) {
            NSWorkspace.shared.activateFileViewerSelecting([
                FileStorage.urlForNote(note),
            ])
        }

        Divider()

        Button(l10n["common.delete"], role: .destructive) {
            noteStore.trashNote(note)
        }
    }

    /// Context menu items for a folder row.
    @ViewBuilder
    static func folderContextMenuItems(
        folder: Folder,
        noteStore: NoteStore,
        l10n: L10n,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void,
    ) -> some View {
        Button(l10n["common.rename"], action: onRename)

        folderMoveMenu(for: folder, noteStore: noteStore, l10n: l10n)

        Button(l10n["common.showInFinder"]) {
            NSWorkspace.shared.activateFileViewerSelecting([
                FileStorage.urlForFolder(folder.name),
            ])
        }

        Divider()

        Button(l10n["common.delete"], role: .destructive, action: onDelete)
    }

    // MARK: - Note Move Menu

    /// "Move to" submenu for a note — lists all available folders as a tree.
    @ViewBuilder
    static func noteMoveMenu(for note: Note, noteStore: NoteStore, l10n: L10n) -> some View {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
        let canMoveToRoot = !note.folder.isEmpty
        if canMoveToRoot || !topLevel.isEmpty {
            Menu(l10n["common.moveTo"]) {
                if canMoveToRoot {
                    Button(l10n["common.root"]) {
                        noteStore.moveNote(note, to: "")
                    }
                }
                ForEach(topLevel) { folder in
                    if folder.name != note.folder {
                        noteMoveTreeItem(folder: folder, note: note, noteStore: noteStore, l10n: l10n)
                    }
                }
            }
        }
    }

    /// Recursive folder tree menu item for note move destinations.
    static func noteMoveTreeItem(folder: Folder, note: Note, noteStore: NoteStore, l10n: L10n) -> AnyView {
        let children = noteStore.childFolders(of: folder.name)
            .filter { $0.name != note.folder }
        if children.isEmpty {
            return AnyView(
                Button(folder.displayName) {
                    noteStore.moveNote(note, to: folder.name)
                },
            )
        } else {
            return AnyView(
                Menu(folder.displayName) {
                    Button(l10n["common.moveHere"]) {
                        noteStore.moveNote(note, to: folder.name)
                    }
                    Divider()
                    ForEach(children) { child in
                        noteMoveTreeItem(folder: child, note: note, noteStore: noteStore, l10n: l10n)
                    }
                },
            )
        }
    }

    // MARK: - Folder Move Menu

    /// "Move to" submenu for a folder — lists valid target locations as a tree.
    @ViewBuilder
    static func folderMoveMenu(for folder: Folder, noteStore: NoteStore, l10n: L10n) -> some View {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
            .filter { $0.name != folder.name && !$0.name.hasPrefix(folder.name + "/") }
        let canMoveToRoot = !folder.isTopLevel
        if canMoveToRoot || !topLevel.isEmpty {
            Menu(l10n["common.moveTo"]) {
                if canMoveToRoot {
                    Button(l10n["common.root"]) {
                        noteStore.moveFolder(folder.name, toParent: "")
                    }
                }
                ForEach(topLevel) { target in
                    folderMoveTreeItem(target: target, movingFolder: folder, noteStore: noteStore, l10n: l10n)
                }
            }
        }
    }

    /// Recursive tree menu item for folder move destinations.
    static func folderMoveTreeItem(target: Folder, movingFolder: Folder, noteStore: NoteStore, l10n: L10n) -> AnyView {
        let isCurrentParent = target.name == movingFolder.parentPath
        let children = noteStore.childFolders(of: target.name)
            .filter { $0.name != movingFolder.name && !$0.name.hasPrefix(movingFolder.name + "/") }

        if isCurrentParent {
            if children.isEmpty {
                return AnyView(EmptyView())
            }
            return AnyView(
                Menu(target.displayName) {
                    ForEach(children) { child in
                        folderMoveTreeItem(target: child, movingFolder: movingFolder, noteStore: noteStore, l10n: l10n)
                    }
                },
            )
        }

        if children.isEmpty {
            return AnyView(
                Button(target.displayName) {
                    noteStore.moveFolder(movingFolder.name, toParent: target.name)
                },
            )
        }

        return AnyView(
            Menu(target.displayName) {
                Button(l10n["common.moveHere"]) {
                    noteStore.moveFolder(movingFolder.name, toParent: target.name)
                }
                Divider()
                ForEach(children) { child in
                    folderMoveTreeItem(target: child, movingFolder: movingFolder, noteStore: noteStore, l10n: l10n)
                }
            },
        )
    }
}
