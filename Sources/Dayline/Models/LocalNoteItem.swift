import Foundation

/// Local note shown in the menu and editor windows.
struct LocalNoteItem: Identifiable, Codable, Equatable {
  /// Stable local note identifier.
  var id: String

  /// Plain-text body for compact display and editing.
  var text: String

  /// Creation timestamp.
  var createdAt: Date

  /// Last update timestamp.
  var updatedAt: Date

  /// Title derived from the first line of the note text.
  var title: String {
    let firstLine = text.components(separatedBy: .newlines).first ?? ""
    let trimmedFirstLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedFirstLine.isEmpty ? "Untitled note" : trimmedFirstLine
  }

  /// Preview text shown under the derived title in the menu.
  var preview: String {
    let lines = text.components(separatedBy: .newlines)
    guard lines.count > 1 else {
      return ""
    }
    return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Creates a local note with only editable text and timestamps.
  init(id: String, text: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.text = text
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// Coding keys, including legacy `title` for migration from the first local-notes build.
  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case text
    case createdAt
    case updatedAt
  }

  /// Decodes notes and folds a legacy title into text if the older body is empty.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    let decodedText = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    text = decodedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? legacyTitle : decodedText
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }

  /// Encodes the local-only note format without a separate title field.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(text, forKey: .text)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(updatedAt, forKey: .updatedAt)
  }
}
