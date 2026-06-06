import Cocoa
import SwiftUI

/// Shared NSMenu builders for note and folder context menus.
/// Uses NSMenu instead of SwiftUI `.contextMenu` so SF Symbol icons render reliably on macOS.
enum NoteListMenus {
    // MARK: - Multi-Selection Context Menu

    /// Build an NSMenu shown when right-clicking on a multi-row selection.
    /// Mirrors the single-row menu shape (Move → Tags → Trash) but operates on
    /// every item in `noteStore.selection` at once.
    static func selectionMenu(noteStore: NoteStore, l10n: L10n) -> NSMenu {
        let menu = NSMenu()
        let count = noteStore.selection.count
        let countString = "\(count)"
        let noteCount = noteStore.selectedNotes.count

        // Move To submenu — always offered (notes always movable; folders skip invalid targets).
        if let moveSubmenu = selectionMoveSubmenu(noteStore: noteStore, l10n: l10n) {
            let moveItem = NSMenuItem(
                title: l10n.t("selection.moveTo", countString),
                action: nil,
                keyEquivalent: "",
            )
            moveItem.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)
            moveItem.submenu = moveSubmenu
            menu.addItem(moveItem)
        }

        // Tags submenu — only meaningful when at least one note is selected.
        if noteCount > 0 {
            let tagsItem = NSMenuItem(
                title: l10n.t("selection.tag", "\(noteCount)"),
                action: nil,
                keyEquivalent: "",
            )
            tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
            tagsItem.submenu = selectionTagsSubmenu(noteStore: noteStore, appSettings: AppSettings.shared)
            menu.addItem(tagsItem)
        }

        menu.addItem(.separator())

        menu.addActionItem(
            title: l10n.t("selection.moveToTrash", countString),
            icon: "trash",
        ) {
            noteStore.trashSelection()
        }
        return menu
    }

    // MARK: - Selection Move Submenu

    private static func selectionMoveSubmenu(noteStore: NoteStore, l10n: L10n) -> NSMenu? {
        let selectedFolders = Set(noteStore.selectedFolderPaths)
        let selectedNoteFolders = Set(noteStore.selectedNotes.map(\.folder))

        // Offer "Root" only when something in the selection isn't already at root —
        // i.e. some selected note has a folder, or some selected folder is nested.
        let everyoneAtRoot = selectedNoteFolders.allSatisfy(\.isEmpty)
            && selectedFolders.allSatisfy { path in
                noteStore.folders.first(where: { $0.name == path })?.isTopLevel ?? true
            }
        let offerRoot = !everyoneAtRoot

        let topLevel = noteStore.folders.filter(\.isTopLevel)
        guard offerRoot || !topLevel.isEmpty else { return nil }

        let submenu = NSMenu()
        if offerRoot {
            submenu.addActionItem(title: l10n["common.root"], icon: "house") {
                noteStore.moveSelection(toFolder: "")
            }
        }
        for folder in topLevel {
            selectionMoveTreeItem(
                folder: folder,
                selectedFolders: selectedFolders,
                noteStore: noteStore,
                l10n: l10n,
                menu: submenu,
            )
        }
        return submenu
    }

    private static func selectionMoveTreeItem(
        folder: Folder,
        selectedFolders: Set<String>,
        noteStore: NoteStore,
        l10n: L10n,
        menu: NSMenu,
    ) {
        // Skip targets that would move a selected folder into itself or a descendant.
        let invalidTarget = selectedFolders.contains(folder.name)
            || selectedFolders.contains(where: { folder.name.hasPrefix($0 + "/") })
        let children = noteStore.childFolders(of: folder.name)

        if children.isEmpty {
            if invalidTarget { return }
            menu.addActionItem(title: folder.displayName, icon: "folder") {
                noteStore.moveSelection(toFolder: folder.name)
            }
        } else {
            let item = NSMenuItem(title: folder.displayName, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let sub = NSMenu()
            if !invalidTarget {
                sub.addActionItem(title: l10n["common.moveHere"], icon: "arrow.right") {
                    noteStore.moveSelection(toFolder: folder.name)
                }
                sub.addItem(.separator())
            }
            for child in children {
                selectionMoveTreeItem(
                    folder: child,
                    selectedFolders: selectedFolders,
                    noteStore: noteStore,
                    l10n: l10n,
                    menu: sub,
                )
            }
            // If the parent was invalid AND its subtree produced no entries,
            // skip adding an empty submenu.
            guard sub.items.contains(where: { !$0.isSeparatorItem }) else { return }
            item.submenu = sub
            menu.addItem(item)
        }
    }

    // MARK: - Selection Tags Submenu

    private static func selectionTagsSubmenu(noteStore: NoteStore, appSettings: AppSettings) -> NSMenu {
        let menu = NSMenu()
        for tag in TagColor.allCases {
            let item = menu.addActionItem(title: appSettings.label(for: tag), icon: "circle.fill") {
                noteStore.toggleTagOnSelection(tag)
            }
            item.image = tagImage(for: tag)
            switch noteStore.tagState(tag) {
            case .on: item.state = .on
            case .off: item.state = .off
            case .mixed: item.state = .mixed
            }
        }
        return menu
    }

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

        // Tags submenu
        let tagsItem = NSMenuItem(title: l10n["common.tags"], action: nil, keyEquivalent: "")
        tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        tagsItem.submenu = tagsSubmenu(for: note, noteStore: noteStore, appSettings: AppSettings.shared)
        menu.addItem(tagsItem)

        menu.addItem(.separator())

        menu.addActionItem(title: l10n["common.copyPlainText"], icon: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.plainText, forType: .string)
        }

        menu.addActionItem(title: l10n["common.copyMarkdown"], icon: "doc.richtext") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.content, forType: .string)
        }

        menu.addActionItem(title: l10n["common.copyRTF"], icon: "textformat") {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let rtf = note.rtfData {
                pb.setData(rtf, forType: .rtf)
            } else {
                pb.setString(note.plainText, forType: .string)
            }
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

    // MARK: - Tags Submenu

    private static func tagsSubmenu(for note: Note, noteStore: NoteStore, appSettings: AppSettings) -> NSMenu {
        let menu = NSMenu()
        let noteID = note.id
        for tag in TagColor.allCases {
            // Reuse the standard MenuDispatch wiring — capture noteID so the toggle
            // always reads the latest note state at click time.
            let item = menu.addActionItem(title: appSettings.label(for: tag), icon: "circle.fill") {
                guard let current = noteStore.notes.first(where: { $0.id == noteID }) else { return }
                noteStore.toggleTag(tag, on: current)
            }
            item.image = tagImage(for: tag)
            item.state = note.tags.contains(tag) ? .on : .off
        }
        return menu
    }

    /// 12pt circle filled with the tag color, used as the menu item icon.
    private static func tagImage(for tag: TagColor) -> NSImage {
        let size: CGFloat = 12
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(tag.color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Folder Color Submenu

    private static func folderColorSubmenu(
        for folder: Folder,
        noteStore: NoteStore,
        l10n: L10n,
    ) -> NSMenu {
        let menu = NSMenu()
        let folderName = folder.name
        let currentColor = folder.color

        for tag in TagColor.allCases {
            // Use the static palette name (Red / Orange / …), not the user's tag label,
            // so renaming a tag does not bleed into the folder color picker.
            let item = menu.addActionItem(title: tag.defaultLabel, icon: "circle.fill") {
                noteStore.setFolderColor(tag, for: folderName)
            }
            item.image = tagImage(for: tag)
            item.state = currentColor == tag ? .on : .off
        }

        menu.addItem(.separator())

        let noneItem = menu.addActionItem(title: l10n["common.none"], icon: "circle") {
            noteStore.setFolderColor(nil, for: folderName)
        }
        noneItem.state = currentColor == nil ? .on : .off

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

        // Folder Color submenu
        let colorItem = NSMenuItem(title: l10n["common.folderColor"], action: nil, keyEquivalent: "")
        colorItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        colorItem.submenu = folderColorSubmenu(for: folder, noteStore: noteStore, l10n: l10n)
        menu.addItem(colorItem)

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
