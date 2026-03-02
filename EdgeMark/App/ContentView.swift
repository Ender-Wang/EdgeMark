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
    private var pageTransition: AnyTransition {
        switch noteStore.navigationDirection {
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
        case .overlay:
            .opacity
        case .none:
            .opacity
        }
    }

    /// Trash uses vertical slide (from bottom).
    private var trashTransition: AnyTransition {
        .asymmetric(
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
        .environment(AppSettings())
        .environment(L10n.shared)
        .frame(width: 400, height: 600)
}
