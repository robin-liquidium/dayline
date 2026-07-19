import Foundation

/// Live connection state for one external account.
struct ConnectionStatus: Identifiable, Equatable {
  /// Provider being connected.
  let provider: AuthProvider

  /// Current connection state.
  var state: ConnectionState

  /// Optional detail shown under the status title or as a secondary Settings label.
  var detail: String?

  /// Connected account label such as an email address.
  var accountLabel: String?

  /// Stable identity.
  var id: String {
    provider.id
  }

  /// Whether this provider can be used for refreshes.
  var isConnected: Bool {
    state == .connected
  }

  /// Human-readable status title.
  var title: String {
    switch state {
    case .checking:
      "Checking \(provider.title)"
    case .disconnected:
      "\(provider.title) is not connected"
    case .connecting:
      "Connecting \(provider.title)"
    case .connected:
      if let accountLabel, !accountLabel.isEmpty {
        "\(provider.title) · \(accountLabel)"
      } else {
        "\(provider.title) is connected"
      }
    }
  }

  /// Initial status list shown before the first token check completes.
  static var checkingAll: [ConnectionStatus] {
    AuthProvider.allCases.map {
      ConnectionStatus(provider: $0, state: .checking, detail: nil, accountLabel: nil)
    }
  }
}

/// Current connection state for one external account.
enum ConnectionState: Equatable {
  /// The app has not checked stored credentials yet.
  case checking

  /// No usable credentials exist; the user needs to connect.
  case disconnected

  /// A browser sign-in is currently in progress.
  case connecting

  /// Stored credentials exist and can be used for API calls.
  case connected
}
