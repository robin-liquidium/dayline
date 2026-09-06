import Testing
@testable import Dayline

struct SettingsSearchTests {
  @Test func searchCombinesWordsAcrossTitlesSectionsAndKeywords() {
    let item = SettingsSearchItem(
      id: "priority", title: "Default priority", section: "New Linear issues",
      tab: .issues, keywords: ["urgent"]
    )
    #expect(item.matches("  LINEAR   urgent priority "))
    #expect(!item.matches("Linear calendar"))
  }

  @Test(arguments: [
    ("crash logs", "exportDiagnostics"),
    ("apple icloud", "appleCalendar"),
    ("notes floating", "notesKeepOnTop"),
    ("hide issue labels", "issueRowFieldLabels")
  ])
  func findsPreviouslyMissingPreferences(query: String, id: String) {
    #expect(SettingsSearchCatalog.items.contains { $0.id == id && $0.matches(query) })
  }
}
