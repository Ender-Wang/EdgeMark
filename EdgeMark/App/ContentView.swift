import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            VisualEffectView()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)

                Text("EdgeMark")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Your notes, one edge away")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
        .frame(width: 400, height: 600)
}
