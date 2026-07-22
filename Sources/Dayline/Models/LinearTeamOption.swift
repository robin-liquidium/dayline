import Foundation

/// Linear estimate choice for a team's estimation scale.
struct LinearEstimateOption: Identifiable, Equatable {
  /// Numeric estimate value sent to Linear.
  let value: Int

  /// Human-readable label, e.g. `3` or `M` for t-shirt scales.
  let label: String

  var id: Int { value }
}

/// Linear team option used by the issue creator.
struct LinearTeamOption: Identifiable, Equatable {
  /// Stable Linear team identifier.
  let id: String

  /// Short Linear team key.
  let key: String

  /// Human-readable team name.
  let name: String

  /// Available workflow states for the team.
  let states: [LinearWorkflowState]

  /// Team estimation scale: `notUsed`, `exponential`, `fibonacci`, `linear`, or `tShirt`.
  let issueEstimationType: String

  /// Whether the team allows an explicit zero estimate.
  let issueEstimationAllowZero: Bool

  /// Whether the team extends its estimation scale with two larger values.
  let issueEstimationExtended: Bool

  /// Compact menu label for pickers.
  var label: String {
    "\(key) - \(name)"
  }

  /// Estimate options for the team's estimation scale, empty when estimates are disabled.
  var estimateOptions: [LinearEstimateOption] {
    let values: [Int]
    var names: [String]?
    switch issueEstimationType {
    case "exponential":
      values = issueEstimationExtended ? [1, 2, 4, 8, 16, 32, 64] : [1, 2, 4, 8, 16]
    case "fibonacci":
      values = issueEstimationExtended ? [1, 2, 3, 5, 8, 13, 21] : [1, 2, 3, 5, 8]
    case "linear":
      values = issueEstimationExtended ? [1, 2, 3, 4, 5, 6, 7] : [1, 2, 3, 4, 5]
    case "tShirt":
      values = issueEstimationExtended ? [1, 2, 3, 5, 8, 13, 21] : [1, 2, 3, 5, 8]
      names = ["XS", "S", "M", "L", "XL", "XXL", "XXXL"]
    default:
      return []
    }

    var options = values.enumerated().map { index, value in
      LinearEstimateOption(value: value, label: names?[index] ?? "\(value)")
    }
    if issueEstimationAllowZero {
      options.insert(LinearEstimateOption(value: 0, label: "0"), at: 0)
    }
    return options
  }
}
