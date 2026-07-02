import Foundation

/// Shared date parsers used by CLI service decoders.
enum DateParsers {
  /// RFC3339 parser for timestamps returned by Google Calendar with fractional seconds.
  private static let fractionalRFC3339: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  /// RFC3339 parser for timestamps returned by Google Calendar without fractional seconds.
  private static let plainRFC3339: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  /// Parses either fractional or plain RFC3339 timestamps.
  static func rfc3339Date(from string: String) -> Date? {
    fractionalRFC3339.date(from: string) ?? plainRFC3339.date(from: string)
  }
}
