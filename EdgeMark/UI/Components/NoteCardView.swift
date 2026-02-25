import SwiftUI

struct NoteCardView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(note.createdAt.homeDisplayFormat)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(previewText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var previewText: String {
        let lines = note.content.split(separator: "\n", omittingEmptySubsequences: true)
        // Skip the first line (usually the title heading)
        let bodyLines = lines.dropFirst()
        let raw = bodyLines.prefix(3).joined(separator: " ")
        // Strip common markdown markers for a cleaner preview
        return raw
            .replacingOccurrences(of: "#{1,6}\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*{1,2}([^*]+)\\*{1,2}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            .prefix(120)
            .description
    }
}
