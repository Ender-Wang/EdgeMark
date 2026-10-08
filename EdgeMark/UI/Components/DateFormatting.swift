import Foundation

extension Date {
    /// Locale-aware display with a textual month and fixed-width numeric fields.
    var homeDisplayFormat: String {
        formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: Locale(identifier: L10n.shared.resolvedLocaleIdentifier),
            )
            .year(.defaultDigits)
            .month(.abbreviated)
            .day(.twoDigits)
            .hour(.twoDigits(amPM: .abbreviated))
            .minute(.twoDigits),
        )
    }
}
