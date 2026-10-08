import SwiftUI

/// Describes a selected row's place within a consecutive selection run.
enum RowSelectionPosition {
    case none
    case single
    case first
    case middle
    case last

    static func resolve(
        _ id: NoteStore.SelectableID,
        in visibleOrder: [NoteStore.SelectableID],
        selection: Set<NoteStore.SelectableID>,
    ) -> Self {
        guard selection.contains(id), let index = visibleOrder.firstIndex(of: id) else {
            return .none
        }

        let joinsPrevious = index > visibleOrder.startIndex
            && selection.contains(visibleOrder[index - 1])
        let joinsNext = index < visibleOrder.index(before: visibleOrder.endIndex)
            && selection.contains(visibleOrder[index + 1])

        switch (joinsPrevious, joinsNext) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    var isSelected: Bool {
        self != .none
    }

    fileprivate var cornerRadii: RectangleCornerRadii {
        let radius = SurfaceMetrics.panelCornerRadius
        switch self {
        case .none, .single:
            return RectangleCornerRadii(
                topLeading: radius,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: radius,
            )
        case .first:
            return RectangleCornerRadii(topLeading: radius, topTrailing: radius)
        case .middle:
            return RectangleCornerRadii()
        case .last:
            return RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)
        }
    }
}

/// Shared selection and hover surface for note and folder rows.
/// Active row states adopt Liquid Glass when enabled; classic mode keeps the established fills.
struct PanelRowBackground: View {
    @Environment(AppSettings.self) private var appSettings

    let isHovered: Bool
    var selectionPosition: RowSelectionPosition = .none

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: selectionPosition.cornerRadii,
            style: .continuous,
        )
    }

    var body: some View {
        if #available(macOS 26.0, *), appSettings.usesLiquidGlass, isHovered || selectionPosition.isSelected {
            shape
                .fill(selectionPosition.isSelected ? Color.accentColor.opacity(0.14) : .clear)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(classicFill)
        }
    }

    private var classicFill: Color {
        if selectionPosition.isSelected {
            return Color.accentColor.opacity(isHovered ? 0.28 : 0.20)
        }
        return Color.primary.opacity(isHovered ? 0.06 : 0)
    }
}
