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
                .background { VisualEffectView().ignoresSafeArea() }
                .opacity(showNoteList ? 1 : 0)
                .allowsHitTesting(showNoteList)

            EditorScreen()
                .background { VisualEffectView().ignoresSafeArea() }
                .opacity(showEditor ? 1 : 0)
                .allowsHitTesting(showEditor)
        }
    }
}

/// NSVisualEffectView wrapper for the translucent panel background.
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

#Preview {
    ContentView()
        .environment(NoteStore())
        .frame(width: 400, height: 600)
}
