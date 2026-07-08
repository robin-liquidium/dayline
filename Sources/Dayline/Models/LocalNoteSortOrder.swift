import Foundation

/// User-selectable ordering for local notes in the menu.
enum LocalNoteSortOrder: String, CaseIterable, Identifiable {
  /// Most recently updated notes first.
  case updatedAt

  /// Most recently created notes first.
  case createdAt

  /// Alphabetical ordering by note title.
  case title

  /// Stable identity for SwiftUI pickers.
  var id: String { rawValue }

  /// Human-readable label for Settings.
  var label: String {
    switch self {
    case .updatedAt:
      "Last updated"
    case .createdAt:
      "Created"
    case .title:
      "Title"
    }
  }
}
