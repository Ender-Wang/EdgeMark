import Foundation

struct Folder: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    var noteCount: Int

    /// Virtual folder representing all notes (unfiltered view).
    static let allNotes = Folder(name: "", noteCount: 0)
}
