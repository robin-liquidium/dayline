import Foundation

/// User-selectable Linear priority values.
struct LinearPriorityOption: CaseIterable, Identifiable, Equatable {
  /// Numeric priority value accepted by Linear.
  let value: Int

  /// Human-readable priority label.
  let label: String

  /// Stable identity for SwiftUI lists.
  var id: Int { value }

  /// Linear's built-in priority choices.
  static let allCases: [LinearPriorityOption] = [
    LinearPriorityOption(value: 1, label: "Urgent"),
    LinearPriorityOption(value: 2, label: "High"),
    LinearPriorityOption(value: 3, label: "Medium"),
    LinearPriorityOption(value: 4, label: "Low"),
    LinearPriorityOption(value: 0, label: "No priority")
  ]
}
