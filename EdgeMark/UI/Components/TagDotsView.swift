import SwiftUI

/// Tiny row of colored dots used inside note rows. Renders nothing for an empty list.
struct TagDotsView: View {
    let tags: [TagColor]
    var size: CGFloat = 8
    var spacing: CGFloat = 3

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: spacing) {
                ForEach(tags, id: \.self) { tag in
                    Circle()
                        .fill(tag.color)
                        .frame(width: size, height: size)
                }
            }
        }
    }
}
