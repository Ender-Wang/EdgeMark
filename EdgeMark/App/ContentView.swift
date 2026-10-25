import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @Environment(PeekCoordinator.self) var peekCoordinator
    @Environment(L10n.self) var l10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showHome: Bool {
        !noteStore.showTrash && noteStore.selectedFolder == nil && noteStore.selectedNote == nil
    }

    private var showNoteList: Bool {
        !noteStore.showTrash && noteStore.selectedFolder != nil && noteStore.selectedNote == nil
    }

    private var showEditor: Bool {
        !noteStore.showTrash && noteStore.selectedNote != nil
    }

    private var usesColumnShell: Bool {
        appSettings.noteViewMode == .column
            && !noteStore.showTrash
            && !noteStore.awaitingRootChoice
    }

    /// Horizontal page transition based on navigation direction.
    /// Falls back to opacity when the user has chosen Fade animation style.
    private var pageTransition: AnyTransition {
        guard PanelSettings.shared.animationStyle == .slide else { return .opacity }
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
        guard PanelSettings.shared.animationStyle == .slide else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom),
            removal: .move(edge: .bottom),
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            if usesColumnShell {
                columnLayout
            } else {
                singlePageLayout
            }

            if let count = noteStore.copiedPathsCount {
                ClipboardFeedbackView(count: count)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: noteStore.copiedPathsCount)
        // Dismiss any open hover/Quick-Look preview when the user navigates
        // deeper (open note, enter folder, open trash). The preview is anchored
        // to a row in the list view we're leaving, so it would otherwise float
        // detached after the transition.
        .onChange(of: noteStore.selectedNote?.id) { _, newID in
            if newID != nil {
                peekCoordinator.dismissNow()
            }
        }
        .onChange(of: noteStore.selectedFolder?.name) { _, newName in
            if newName != nil {
                peekCoordinator.dismissNow()
            }
        }
        .onChange(of: noteStore.showTrash) { _, isOn in
            if isOn {
                peekCoordinator.dismissNow()
            }
        }
    }

    private var singlePageLayout: some View {
        ZStack {
            // HomeFolderView hosts the storage-root picker inside the shared surface
            // (header + content swap), so when awaitingRootChoice it shows the
            // picker rows; picking crossfades to the folder list within the same
            // stable content layer. No separate nested surface is introduced.
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
    }

    private var columnLayout: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - 24, 0)
            let isWide = geometry.size.width >= PanelLayoutMetrics.columnBreakpoint
            let showsBrowser = isWide || noteStore.selectedNote == nil
            let browserWidth = if isWide {
                PanelLayoutMetrics.navigationWidth(for: usableWidth)
            } else {
                showsBrowser ? usableWidth : 0
            }

            HStack(spacing: isWide ? PanelLayoutMetrics.paneSpacing : 0) {
                columnBrowser(isWide: isWide)
                    .frame(width: browserWidth)
                    .frame(maxHeight: .infinity)
                    .opacity(showsBrowser ? 1 : 0)
                    .allowsHitTesting(showsBrowser)
                    .accessibilityHidden(!showsBrowser)
                    .clipped()

                if let note = noteStore.selectedNote {
                    EditorScreen(
                        pagePresentation: .embedded,
                        showsBackButton: !isWide,
                    )
                    .id(note.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isWide {
                    emptyColumnDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isWide)
        }
    }

    @ViewBuilder
    private func columnBrowser(isWide: Bool) -> some View {
        if noteStore.selectedFolder == nil {
            HomeFolderView(
                pagePresentation: .embedded,
                opensNotesOnSingleClick: isWide,
            )
        } else {
            NoteListView(
                pagePresentation: .embedded,
                opensNotesOnSingleClick: isWide,
                isPersistentBrowser: isWide,
            )
            .id(noteStore.selectedFolder?.name)
        }
    }

    private var emptyColumnDetail: some View {
        PageLayout(presentation: .embedded) {
            Text(l10n["column.detail.header"])
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: l10n["column.detail.empty.title"],
                subtitle: l10n["column.detail.empty.subtitle"],
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n["column.detail.empty.title"])
    }
}

#Preview {
    ContentView()
        .environment(NoteStore())
        .environment(AppSettings.shared)
        .environment(L10n.shared)
        .environment(PeekCoordinator())
        .frame(width: 400, height: 600)
}
