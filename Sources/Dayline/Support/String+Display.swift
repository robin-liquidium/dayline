import Foundation

/// Small string helpers for fitting external data into compact menu rows.
extension String {
  /// Returns a single-line string capped to a reasonable visual length.
  func compactLine(limit: Int = 64) -> String {
    let flattened = replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard flattened.count > limit else {
      return flattened
    }
    return String(flattened.prefix(max(0, limit - 3))) + "..."
  }
}
