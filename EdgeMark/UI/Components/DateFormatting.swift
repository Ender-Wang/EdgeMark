import Foundation

extension Date {
    /// Locale-aware date display: "18:30 Feb 25, 2026" (en) or "2026年2月25日 18:30" (zh).
    var homeDisplayFormat: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.shared.resolvedLocaleIdentifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
