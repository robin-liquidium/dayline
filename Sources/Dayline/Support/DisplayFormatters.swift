import Foundation

/// Shared display formatters for compact menu bar text.
enum DisplayFormatters {
  /// Time formatter for event start and end times.
  static let time: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter
  }()

  /// Relative formatter for the last refresh timestamp.
  static let relative: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
  }()

  /// Date-time formatter for local note metadata.
  static let noteTimestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  /// Formats an event time range for one-line display.
  static func eventTimeRange(start: Date, end: Date, now: Date = Date()) -> String {
    if start <= now && end > now {
      return "Now until \(time.string(from: end))"
    }
    return "\(time.string(from: start))-\(time.string(from: end))"
  }

  /// Formats a meeting start time for compact menu bar countdown text.
  static func menuBarEventStart(_ start: Date, now: Date = Date()) -> String {
    let secondsUntilStart = start.timeIntervalSince(now)
    guard secondsUntilStart > 30 else {
      return "now"
    }

    let minutesUntilStart = max(1, Int(ceil(secondsUntilStart / 60)))
    return "in \(minutesUntilStart)m"
  }

  /// Formats the last updated timestamp for the header.
  static func lastUpdated(_ date: Date?) -> String {
    guard let date else {
      return "Not updated yet"
    }
    let elapsed = Date().timeIntervalSince(date)
    guard elapsed >= 5 else {
      return "Updated now"
    }
    return "Updated \(relative.localizedString(fromTimeInterval: -elapsed))"
  }

  /// Formats a Linear `YYYY-MM-DD` due date for compact metadata.
  static func linearDueDate(_ rawDate: String) -> String {
    let input = DateFormatter()
    input.locale = Locale(identifier: "en_US_POSIX")
    input.dateFormat = "yyyy-MM-dd"

    guard let date = input.date(from: rawDate) else {
      return rawDate
    }

    let output = DateFormatter()
    output.dateStyle = .medium
    output.timeStyle = .none
    return output.string(from: date)
  }

  /// Formats a local note timestamp for compact metadata.
  static func noteDate(_ date: Date) -> String {
    noteTimestamp.string(from: date)
  }
}
