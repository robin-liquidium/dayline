import Foundation

/// Persists Dayline notes as a small JSON file in Application Support.
struct LocalNotesService {
  /// File URL used for note storage.
  var fileURL = Self.defaultFileURL

  /// Loads locally persisted notes, returning an empty list when no file exists yet.
  func loadNotes() throws -> [LocalNoteItem] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }

    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode([LocalNoteItem].self, from: data)
    } catch {
      return try JSONDecoder().decode([LocalNoteItem].self, from: data)
    }
  }

  /// Saves the full local note collection atomically.
  func saveNotes(_ notes: [LocalNoteItem]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(notes)
    try data.write(to: fileURL, options: [.atomic])
  }

  /// Default Application Support file for Dayline notes.
  private static var defaultFileURL: URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return baseURL
      .appendingPathComponent("Dayline", isDirectory: true)
      .appendingPathComponent("notes.json")
  }
}
