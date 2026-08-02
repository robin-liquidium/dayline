import Foundation

/// Priority levels exposed by Apple Reminders through EventKit.
enum AppleReminderPriority: Int, CaseIterable, Codable, Identifiable, Sendable {
  /// High priority, represented by EventKit values 1 through 4.
  case high = 1

  /// Medium priority, represented by EventKit value 5.
  case medium = 5

  /// Low priority, represented by EventKit values 6 through 9.
  case low = 9

  /// No priority.
  case none = 0

  /// Stable SwiftUI identity.
  var id: Int { rawValue }

  /// Human-readable priority label.
  var label: String {
    switch self {
    case .high: "High"
    case .medium: "Medium"
    case .low: "Low"
    case .none: "No priority"
    }
  }

  /// Sort rank that places explicit priorities before unprioritized reminders.
  var sortRank: Int {
    switch self {
    case .high: 0
    case .medium: 1
    case .low: 2
    case .none: 3
    }
  }

  /// Normalizes EventKit's RFC 5545 priority range into Reminders' four UI levels.
  init(eventKitValue: Int) {
    switch eventKitValue {
    case 1...4: self = .high
    case 5: self = .medium
    case 6...9: self = .low
    default: self = .none
    }
  }
}
