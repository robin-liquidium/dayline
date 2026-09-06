import AppKit

enum IssueClickAction: String, CaseIterable, Identifiable {
  case showDetails
  case openInBrowser

  var id: String { rawValue }

  var label: String {
    switch self {
    case .showDetails: "Show details"
    case .openInBrowser: "Open in browser"
    }
  }

  var alternate: Self {
    self == .showDetails ? .openInBrowser : .showDetails
  }

  func resolved(modifiers: NSEvent.ModifierFlags, alternateModifier: IssueClickModifier) -> Self {
    modifiers.contains(alternateModifier.flags) ? alternate : self
  }
}

enum IssueClickModifier: String, CaseIterable, Identifiable {
  case command
  case option
  case shift

  var id: String { rawValue }

  var label: String {
    switch self {
    case .command: "Command (⌘)"
    case .option: "Option (⌥)"
    case .shift: "Shift (⇧)"
    }
  }

  var flags: NSEvent.ModifierFlags {
    switch self {
    case .command: .command
    case .option: .option
    case .shift: .shift
    }
  }
}
