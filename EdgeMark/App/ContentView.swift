import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) var noteStore

    private var showHome: Bool {
        noteStore.selectedFolder == nil && noteStore.selectedNote == nil
    }

    private var showNoteList: Bool {
        noteStore.selectedFolder != nil && noteStore.selectedNote == nil
    }

    private var showEditor: Bool {
        noteStore.selectedNote != nil
    }

    var body: some View {
        ZStack {
            HomeFolderView()
                .opacity(showHome ? 1 : 0)
                .allowsHitTesting(showHome)

            NoteListView()
                .opacity(showNoteList ? 1 : 0)
                .allowsHitTesting(showNoteList)

            EditorScreen()
                .opacity(showEditor ? 1 : 0)
                .allowsHitTesting(showEditor)
        }
    }
}

#Preview {
    ContentView()
        .environment(NoteStore())
        .environment(AppSettings())
        .frame(width: 400, height: 600)
}
