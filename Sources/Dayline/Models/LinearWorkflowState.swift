import Foundation

/// A workflow status that can be assigned to a Linear issue.
struct LinearWorkflowState: Identifiable, Equatable {
  /// Stable Linear workflow state identifier.
  let id: String

  /// Human-readable workflow state name.
  let name: String

  /// Linear state type, such as `started`, `completed`, or `backlog`.
  let type: String

  /// Numeric workflow position used for native ordering.
  let position: Double
}
