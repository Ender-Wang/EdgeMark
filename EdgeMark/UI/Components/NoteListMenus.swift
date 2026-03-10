import Cocoa
import SwiftUI

/// Shared NSMenu builders for note and folder context menus.
/// Uses NSMenu instead of SwiftUI `.contextMenu` so SF Symbol icons render reliably on macOS.
enum NoteListMenus {
    // MARK: - Note Context Menu

    /// Build an NSMenu for a note row context menu.
    static func noteMenu(
        note: Note,
        noteStore: NoteStore,
        l10n: L10n,
        onRename: @escaping () -> Void,
    ) -> NSMenu {
        let menu = NSMenu()

        menu.addActionItem(title: l10n["common.rename"], icon: "pencil", action: onRename)

        // Move To submenu
        if let moveSubmenu = noteMoveSubmenu(for: note, noteStore: noteStore, l10n: l10n) {
            let moveItem = NSMenuItem(title: l10n["common.moveTo"], action: nil, keyEquivalent: "")
            moveItem.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)
            moveItem.submenu = moveSubmenu
            menu.addItem(moveItem)
        }

        menu.addItem(.separator())

        menu.addActionItem(title: l10n["common.copyPlainText"], icon: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.plainText, forType: .string)
        }

        menu.addActionItem(title: l10n["common.copyMarkdown"], icon: "doc.richtext") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.content, forType: .string)
        }

        menu.addItem(.separator())

        menu.addActionItem(title: l10n["common.showInFinder"], icon: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([
                FileStorage.urlForNote(note),
            ])
        }

        menu.addItem(.separator())

        menu.addActionItem(title: l10n["common.delete"], icon: "trash") {
            noteStore.trashNote(note)
        }

        return menu
    }

    // MARK: - Folder Context Menu

    /// Build an NSMenu for a folder row context menu.
    static func folderMenu(
        folder: Folder,
        noteStore: NoteStore,
        l10n: L10n,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void,
    ) -> NSMenu {
        let menu = NSMenu()

        menu.addActionItem(title: l10n["common.rename"], icon: "pencil", action: onRename)

        // Move To submenu
        if let moveSubmenu = folderMoveSubmenu(for: folder, noteStore: noteStore, l10n: l10n) {
            let moveItem = NSMenuItem(title: l10n["common.moveTo"], action: nil, keyEquivalent: "")
            moveItem.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)
            moveItem.submenu = moveSubmenu
            menu.addItem(moveItem)
        }

        menu.addActionItem(title: l10n["common.showInFinder"], icon: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([
                FileStorage.urlForFolder(folder.name),
            ])
        }

        menu.addItem(.separator())

        menu.addActionItem(title: l10n["common.delete"], icon: "trash", action: onDelete)

        return menu
    }

    // MARK: - Note Move Submenu

    private static func noteMoveSubmenu(for note: Note, noteStore: NoteStore, l10n: L10n) -> NSMenu? {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
        let canMoveToRoot = !note.folder.isEmpty
        guard canMoveToRoot || !topLevel.isEmpty else { return nil }

        let submenu = NSMenu()

        if canMoveToRoot {
            submenu.addActionItem(title: l10n["common.root"], icon: "house") {
                noteStore.moveNote(note, to: "")
            }
        }

        for folder in topLevel where folder.name != note.folder {
            noteMoveTreeItem(folder: folder, note: note, noteStore: noteStore, l10n: l10n, menu: submenu)
        }

        return submenu
    }

    private static func noteMoveTreeItem(
        folder: Folder,
        note: Note,
        noteStore: NoteStore,
        l10n: L10n,
        menu: NSMenu,
    ) {
        let children = noteStore.childFolders(of: folder.name)
            .filter { $0.name != note.folder }

        if children.isEmpty {
            menu.addActionItem(title: folder.displayName, icon: "folder") {
                noteStore.moveNote(note, to: folder.name)
            }
        } else {
            let item = NSMenuItem(title: folder.displayName, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let sub = NSMenu()
            sub.addActionItem(title: l10n["common.moveHere"], icon: "arrow.right") {
                noteStore.moveNote(note, to: folder.name)
            }
            sub.addItem(.separator())
            for child in children {
                noteMoveTreeItem(folder: child, note: note, noteStore: noteStore, l10n: l10n, menu: sub)
            }
            item.submenu = sub
            menu.addItem(item)
        }
    }

    // MARK: - Folder Move Submenu

    private static func folderMoveSubmenu(for folder: Folder, noteStore: NoteStore, l10n: L10n) -> NSMenu? {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
            .filter { $0.name != folder.name && !$0.name.hasPrefix(folder.name + "/") }
        let canMoveToRoot = !folder.isTopLevel
        guard canMoveToRoot || !topLevel.isEmpty else { return nil }

        let submenu = NSMenu()

        if canMoveToRoot {
            submenu.addActionItem(title: l10n["common.root"], icon: "house") {
                noteStore.moveFolder(folder.name, toParent: "")
            }
        }

        for target in topLevel {
            folderMoveTreeItem(target: target, movingFolder: folder, noteStore: noteStore, l10n: l10n, menu: submenu)
        }

        return submenu
    }

    private static func folderMoveTreeItem(
        target: Folder,
        movingFolder: Folder,
        noteStore: NoteStore,
        l10n: L10n,
        menu: NSMenu,
    ) {
        let isCurrentParent = target.name == movingFolder.parentPath
        let children = noteStore.childFolders(of: target.name)
            .filter { $0.name != movingFolder.name && !$0.name.hasPrefix(movingFolder.name + "/") }

        if isCurrentParent {
            guard !children.isEmpty else { return }
            let item = NSMenuItem(title: target.displayName, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let sub = NSMenu()
            for child in children {
                folderMoveTreeItem(target: child, movingFolder: movingFolder, noteStore: noteStore, l10n: l10n, menu: sub)
            }
            item.submenu = sub
            menu.addItem(item)
            return
        }

        if children.isEmpty {
            menu.addActionItem(title: target.displayName, icon: "folder") {
                noteStore.moveFolder(movingFolder.name, toParent: target.name)
            }
        } else {
            let item = NSMenuItem(title: target.displayName, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let sub = NSMenu()
            sub.addActionItem(title: l10n["common.moveHere"], icon: "arrow.right") {
                noteStore.moveFolder(movingFolder.name, toParent: target.name)
            }
            sub.addItem(.separator())
            for child in children {
                folderMoveTreeItem(target: child, movingFolder: movingFolder, noteStore: noteStore, l10n: l10n, menu: sub)
            }
            item.submenu = sub
            menu.addItem(item)
        }
    }
}
