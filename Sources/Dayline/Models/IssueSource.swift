import Foundation

/// Which provider supplies the issues section of the menu.
enum IssueSource: String, CaseIterable, Identifiable, Sendable {
  /// Linear workspace issues.
  case linear

  /// GitHub issues assigned to the user.
  case github

  /// Incomplete reminders from selected Apple Reminders lists.
  case reminders

  /// Stable identity.
  var id: String {
    rawValue
  }

  /// Human-readable source name.
  var label: String {
    switch self {
    case .linear:
      "Linear"
    case .github:
      "GitHub"
    case .reminders:
      "Reminders"
    }
  }

  /// Returns issue sources in stable tab order for the currently usable providers.
  static func available(
    linear: Bool,
    github: Bool,
    reminders: Bool
  ) -> [IssueSource] {
    allCases.filter { source in
      switch source {
      case .linear: linear
      case .github: github
      case .reminders: reminders
      }
    }
  }
}

/// One tab in the menu's work section.
enum MenuTab: Hashable, Identifiable, Sendable {
  /// Items from one issue provider.
  case issues(IssueSource)

  /// Local notes on this Mac.
  case notes

  var id: String {
    switch self {
    case .issues(let source): source.id
    case .notes: "notes"
    }
  }

  var label: String {
    switch self {
    case .issues(let source): source.label
    case .notes: "Notes"
    }
  }
}

/// Day shown in the menu's calendar section.
enum CalendarDay: String, CaseIterable, Identifiable, Sendable {
  case today
  case tomorrow

  var id: String { rawValue }

  var label: String {
    switch self {
    case .today: "Up Next"
    case .tomorrow: "Tomorrow"
    }
  }
}
