import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        ZStack {
            VisualEffectView()
                .ignoresSafeArea()

            NoteListView()
                .opacity(noteStore.selectedNote == nil ? 1 : 0)
                .allowsHitTesting(noteStore.selectedNote == nil)

            EditorScreen()
                .opacity(noteStore.selectedNote != nil ? 1 : 0)
                .allowsHitTesting(noteStore.selectedNote != nil)
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
