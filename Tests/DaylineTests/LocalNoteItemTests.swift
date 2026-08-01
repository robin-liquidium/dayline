@testable import Dayline
import Foundation
import Testing

struct LocalNoteItemTests {
  @Test func titleUsesRenderedMarkdownText() {
    let cases: [(source: String, expected: String)] = [
      ("# Heading", "Heading"),
      ("## Heading **bold** *italic* `code`", "Heading bold italic code"),
      ("[Dayline](https://dayline.robin.build)", "Dayline"),
      ("~~Finished~~", "Finished"),
      ("- [ ] Task", "[ ] Task"),
      ("Literal [brackets]", "Literal [brackets]"),
      ("[](/empty-link)", "Untitled note"),
    ]

    for testCase in cases {
      let note = makeNote(text: testCase.source)
      #expect(note.title == testCase.expected)
    }
  }

  @Test func titleUsesOnlyTheFirstLine() {
    let note = makeNote(text: "# Visible title\n**Body markers stay in the body.**")
    #expect(note.title == "Visible title")
  }

  @Test func emptyFirstLineRemainsUntitled() {
    let note = makeNote(text: "\n# Later heading")
    #expect(note.title == "Untitled note")
  }

  @Test func markdownOnlyFirstLineRemainsUntitled() {
    let note = makeNote(text: "[](/empty-link)\nVisible body")
    #expect(note.title == "Untitled note")
  }

  private func makeNote(text: String) -> LocalNoteItem {
    LocalNoteItem(id: "test-note", text: text, createdAt: .distantPast, updatedAt: .distantPast)
  }
}
