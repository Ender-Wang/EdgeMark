import SwiftUI

/// Fixed Finder-style tag palette. Persisted as raw lowercased strings in YAML
/// front matter so the file stays portable in any external Markdown editor.
enum TagColor: String, CaseIterable, Codable, Hashable {
    case red, orange, yellow, green, blue, purple, gray

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }

    /// Default label used when the user has not customized this tag's name.
    var defaultLabel: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .gray: "Gray"
        }
    }
}
