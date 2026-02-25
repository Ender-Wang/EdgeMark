import Foundation

extension Date {
    /// Format: "18:30 Feb 25, 2026"
    var homeDisplayFormat: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm MMM d, yyyy"
        return formatter.string(from: self)
    }
}
