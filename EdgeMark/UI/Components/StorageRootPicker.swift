import SwiftUI

/// Non-blocking storage-root picker shown as the panel's empty state when
/// `NoteStore.awaitingRootChoice` is true (i.e. "Choose on launch" is on and ≥2
/// roots are configured). Picking a root switches to it for the session
/// (temporary) and clears the flag; no modal sheet — pick → list fills in place.
/// Single tinted card (title + rows + toggle merged), matching the other screens.
struct StorageRootPicker: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(L10n.self) var l10n
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        VStack {
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 2) {
                    Label(l10n["picker.chooseStorageLocation"], systemImage: "folder")
                        .font(.headline)
                    Text(l10n["menu.storageTemporary"])
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                ForEach(ShortcutSettings.shared.storageRoots) { root in
                    Button {
                        pick(root)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(root.displayName)
                                    .font(.body)
                                Text(root.url.path(percentEncoded: false))
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: 360, alignment: .leading)
            .background { VisualEffectView(tint: appSettings.panelTint.color, material: appSettings.panelStyle.material) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pick(_ root: StorageRoot) {
        noteStore.awaitingRootChoice = false
        AppDelegate.shared?.switchRoot(to: root, temporary: true)
    }
}
