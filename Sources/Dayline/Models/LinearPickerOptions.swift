import Foundation
import SwiftUI

/// SwiftUI color parsed from a Linear hex color string.
extension Color {
  /// Creates a color from a hex string such as `#FF5500`, falling back to gray.
  init(linearHex hex: String) {
    var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if digits.hasPrefix("#") {
      digits.removeFirst()
    }
    var value: UInt64 = 0
    guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else {
      self = .gray
      return
    }
    self = Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}

/// Linear project option used by the issue creator.
struct LinearProjectOption: Identifiable, Equatable {
  /// Stable Linear project identifier.
  let id: String

  /// Human-readable project name.
  let name: String

  /// Compact menu label for pickers.
  var label: String {
    name
  }
}

/// Linear cycle option used by the issue creator.
struct LinearCycleOption: Identifiable, Equatable {
  /// Stable Linear cycle identifier.
  let id: String

  /// Linear cycle number within the team.
  let number: Int

  /// Optional human-readable cycle name.
  let name: String

  /// Compact menu label for pickers.
  var label: String {
    name.isEmpty ? "Cycle \(number)" : "Cycle \(number) - \(name)"
  }
}

/// Linear issue label option used by the issue creator.
struct LinearLabelOption: Identifiable, Equatable {
  /// Stable Linear label identifier.
  let id: String

  /// Human-readable label name.
  let name: String

  /// Linear label color as a hex string such as `#FF5500`.
  let color: String

  /// Compact menu label for pickers.
  var label: String {
    name
  }
}

/// Linear project milestone option used by the issue creator.
struct LinearMilestoneOption: Identifiable, Equatable {
  /// Stable Linear milestone identifier.
  let id: String

  /// Human-readable milestone name.
  let name: String

  /// Compact menu label for pickers.
  var label: String {
    name
  }
}
