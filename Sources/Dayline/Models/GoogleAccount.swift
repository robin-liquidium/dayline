import Foundation

/// One Google calendar exposed in Dayline's per-account picker.
struct GoogleCalendarSource: Codable, Identifiable, Equatable, Sendable {
  /// Google Calendar API identifier.
  let id: String

  /// Current display name from Google Calendar.
  var name: String

  /// Whether this is the account's primary calendar.
  var isPrimary: Bool

  /// Whether Dayline includes this calendar in the merged agenda.
  var isEnabled: Bool
}

/// Persisted metadata for one linked Google account.
struct GoogleAccount: Codable, Identifiable, Equatable, Sendable {
  /// Stable local identifier used to namespace credentials.
  let id: UUID

  /// Stable Google identity, normally the primary calendar's email address.
  var providerAccountID: String?

  /// Human-readable account label shown in Settings.
  var displayLabel: String?

  /// Calendars discovered for this account and their Dayline selections.
  var calendars: [GoogleCalendarSource]

  /// Keychain item holding this account's OAuth token bundle.
  var credentialAccount: String {
    "google.\(id.uuidString.lowercased())"
  }

  /// Best available Settings label while legacy credentials are being discovered.
  var label: String {
    displayLabel ?? providerAccountID ?? "Google account"
  }

  /// Merges a fresh Google calendar catalog while preserving explicit Dayline choices.
  func reconcilingCalendars(_ discovered: [GoogleCalendarSource]) -> GoogleAccount {
    let existingSelections = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.isEnabled) })
    var copy = self
    copy.calendars = discovered
      .map { source in
        var source = source
        if let isEnabled = existingSelections[source.id] {
          source.isEnabled = isEnabled
        }
        return source
      }
      .sorted { lhs, rhs in
        if lhs.isPrimary != rhs.isPrimary {
          return lhs.isPrimary
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
    return copy
  }
}

/// Runtime connection state for one persisted Google account.
struct GoogleAccountStatus: Identifiable, Equatable {
  var account: GoogleAccount
  var state: ConnectionState
  var detail: String?

  var id: UUID {
    account.id
  }

  var isConnected: Bool {
    state == .connected
  }

  var needsAttention: Bool {
    state == .disconnected
  }
}
