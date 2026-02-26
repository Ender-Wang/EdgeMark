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

            Text(note.previewText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
