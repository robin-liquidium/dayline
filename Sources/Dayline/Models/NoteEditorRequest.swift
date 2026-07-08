import Foundation

/// Codable window value used to open new or existing note editor windows.
enum NoteEditorRequest: Codable, Hashable {
  /// A blank editor for creating a new note.
  case new

  /// An editor seeded from an existing local note resource name.
  case existing(String)

  /// Whether this request opens an existing note.
  var isExisting: Bool {
    if case .existing = self {
      return true
    }
    return false
  }
}
