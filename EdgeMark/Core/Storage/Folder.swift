import Foundation

struct Folder: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    var noteCount: Int
}
