import SwiftUI

/// Sidebar filter strip showing one button per tag color in use.
/// Click to toggle a tag in the active filter (multi-select acts as OR).
/// Hides itself when no tags are in use.
struct TagFilterBar: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(L10n.self) private var l10n
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        let used = noteStore.allUsedTags
        let ordered = TagColor.allCases.filter { used.contains($0) }
        if !ordered.isEmpty {
            HStack(spacing: 6) {
                ForEach(ordered, id: \.self) { tag in
                    TagFilterDot(tag: tag, isActive: noteStore.activeTagFilter.contains(tag)) {
                        noteStore.toggleTagFilter(tag)
                    }
                    .help(appSettings.label(for: tag))
                }
                if !noteStore.activeTagFilter.isEmpty {
                    Button {
                        noteStore.clearTagFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n["tags.clearFilter"])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

private struct TagFilterDot: View {
    let tag: TagColor
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    /// When any tag is active, inactive dots dim. When nothing is active (no filter),
    /// all dots show at full strength so the bar reads as available, not "all off."
    private var dotOpacity: Double {
        isActive ? 1.0 : (isHovered ? 0.85 : 0.45)
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(tag.color)
                .opacity(dotOpacity)
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isActive)
    }
}
