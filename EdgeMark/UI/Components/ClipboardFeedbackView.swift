import SwiftUI

struct ClipboardFeedbackView: View {
    @Environment(L10n.self) private var l10n

    let count: Int

    private var message: String {
        count == 1 ? l10n["feedback.copiedPath"] : l10n.t("feedback.copiedPaths", "\(count)")
    }

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .accessibilityLabel(message)
    }
}
