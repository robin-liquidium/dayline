import Foundation

/// Public issue category selected by the person submitting feedback.
enum FeedbackCategory: String, CaseIterable, Identifiable, Codable {
  case bug
  case feature
  case other

  var id: String { rawValue }

  /// Human-readable picker label.
  var label: String {
    switch self {
    case .bug:
      "Bug"
    case .feature:
      "Feature"
    case .other:
      "Other"
    }
  }
}
