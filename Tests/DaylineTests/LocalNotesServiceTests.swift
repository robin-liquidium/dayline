import Foundation
import Testing
@testable import Dayline

struct LocalNotesServiceTests {
  @Test func complexMarkdownRoundTripsWithoutModification() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-note-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = """
    # Markdown regression

    This longer paragraph has *italic words*, **bold words**, and ***bold italic words*** without losing text.

    * First bullet with *nested emphasis*
    * Second bullet with **strong text**
    * Third bullet remains visible after a long wrapping sentence with emoji 🚀 and café.
    """
    let note = LocalNoteItem(
      id: "markdown-regression",
      text: source,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let service = LocalNotesService(fileURL: directory.appendingPathComponent("notes.json"))

    try service.saveNotes([note])
    let restored = try service.loadNotes()

    #expect(restored == [note])
    #expect(restored.first?.text == source)
  }
}
