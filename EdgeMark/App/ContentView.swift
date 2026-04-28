import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) var noteStore

    private var showHome: Bool {
        !noteStore.showTrash && noteStore.selectedFolder == nil && noteStore.selectedNote == nil
    }

    private var showNoteList: Bool {
        !noteStore.showTrash && noteStore.selectedFolder != nil && noteStore.selectedNote == nil
    }

    private var showEditor: Bool {
        !noteStore.showTrash && noteStore.selectedNote != nil
    }

    /// Horizontal page transition based on navigation direction.
    /// Falls back to opacity when the user has chosen Fade animation style.
    private var pageTransition: AnyTransition {
        guard ShortcutSettings.shared.animationStyle == .slide else { return .opacity }
        switch noteStore.navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading),
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing),
            )
        case .overlay, .none:
            return .opacity
        }
    }

    /// Trash uses vertical slide (from bottom), or opacity in Fade mode.
    private var trashTransition: AnyTransition {
        guard ShortcutSettings.shared.animationStyle == .slide else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom),
            removal: .move(edge: .bottom),
        )
    }

    var body: some View {
        ZStack {
            if showHome {
                HomeFolderView()
                    .transition(pageTransition)
            }

            if showNoteList {
                NoteListView()
                    .id(noteStore.selectedFolder?.name)
                    .transition(pageTransition)
            }

            if showEditor {
                EditorScreen()
                    .id(noteStore.selectedNote?.id)
                    .transition(pageTransition)
            }

            if noteStore.showTrash {
                TrashView()
                    .transition(trashTransition)
            }
        }
        .clipped()
    }
}

#Preview {
    ContentView()
        .environment(NoteStore())
        .environment(AppSettings.shared)
        .environment(L10n.shared)
        .frame(width: 400, height: 600)
}
