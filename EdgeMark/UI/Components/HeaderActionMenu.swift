import SwiftUI

/// A compact overflow control that reveals header actions on hover and click.
/// The popover preserves the header's layout, so titles never move as actions appear.
struct HeaderActionMenu<MenuContent: View>: View {
    let systemName: String
    let help: String
    let arrowEdge: Edge
    private let menuContent: (@escaping () -> Void) -> MenuContent

    @State private var isPresented = false
    @State private var revealTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?

    init(
        systemName: String = "ellipsis",
        help: String,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> MenuContent,
    ) {
        self.systemName = systemName
        self.help = help
        self.arrowEdge = arrowEdge
        menuContent = content
    }

    var body: some View {
        AdaptiveIconButton(
            systemName: systemName,
            help: help,
            isActive: isPresented,
        ) {
            cancelScheduledTransitions()
            isPresented.toggle()
        }
        .onHover { hovering in
            if hovering {
                scheduleReveal()
            } else {
                scheduleDismiss()
            }
        }
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: arrowEdge,
        ) {
            menuContent(dismiss)
                .padding(6)
                .frame(minWidth: 190)
                .onHover { hovering in
                    if hovering {
                        dismissTask?.cancel()
                    } else {
                        scheduleDismiss()
                    }
                }
        }
        .onDisappear(perform: cancelScheduledTransitions)
    }

    private func scheduleReveal() {
        dismissTask?.cancel()
        guard !isPresented else { return }
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            isPresented = true
        }
    }

    private func scheduleDismiss() {
        revealTask?.cancel()
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }

    private func dismiss() {
        cancelScheduledTransitions()
        isPresented = false
    }

    private func cancelScheduledTransitions() {
        revealTask?.cancel()
        dismissTask?.cancel()
    }
}

/// A full-width action row used inside `HeaderActionMenu` popovers.
struct HeaderActionButton: View {
    let title: String
    let systemName: String
    var role: ButtonRole?
    var isSelected = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 16)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.1 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundColor: Color {
        if role == .destructive, isHovered {
            return .red
        }
        return isHovered ? .primary : .secondary
    }
}
