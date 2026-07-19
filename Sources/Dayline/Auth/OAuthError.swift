import Foundation

/// Failure cases surfaced by OAuth sign-in and token handling.
enum OAuthError: LocalizedError {
  /// No client ID is configured for the provider.
  case notConfigured

  /// No tokens exist for the provider yet.
  case notSignedIn

  /// The user dismissed the browser sign-in.
  case authorizationCancelled

  /// The browser sign-in failed before a callback was produced.
  case authorizationFailed(String)

  /// The callback URL did not contain a usable authorization response.
  case invalidCallback

  /// The callback state does not match the request state.
  case stateMismatch

  /// The provider rejected the authorization code exchange.
  case tokenExchangeFailed(String)

  /// The provider rejected the refresh token.
  case refreshFailed(String)

  /// Stored credentials are no longer accepted; the user must sign in again.
  case reauthenticationRequired

  /// The provider API returned a non-success status.
  case httpError(Int, String)

  /// Human-readable error text.
  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "This build is missing its OAuth client ID."
    case .notSignedIn:
      "You are not signed in."
    case .authorizationCancelled:
      "Sign-in was cancelled."
    case .authorizationFailed(let detail):
      detail.isEmpty ? "Sign-in failed." : detail
    case .invalidCallback:
      "The sign-in response was not valid."
    case .stateMismatch:
      "The sign-in response did not match the request. Please try again."
    case .tokenExchangeFailed(let detail):
      detail.isEmpty ? "Could not finish sign-in." : detail
    case .refreshFailed(let detail):
      detail.isEmpty ? "Could not refresh your session." : detail
    case .reauthenticationRequired:
      "Your session expired. Sign in again."
    case .httpError(let status, let detail):
      Self.friendlyAPIMessage(from: detail)
        ?? (detail.isEmpty ? "Request failed with status \(status)." : detail)
    }
  }

  /// Extracts a human-readable message from a Google or Linear JSON error body.
  private static func friendlyAPIMessage(from detail: String) -> String? {
    guard let data = detail.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    if let error = object["error"] as? [String: Any] {
      if let message = error["message"] as? String, !message.isEmpty {
        return message
      }
      if let errors = error["errors"] as? [[String: Any]],
         let message = errors.first?["message"] as? String,
         !message.isEmpty {
        return message
      }
    }

    if let message = object["message"] as? String, !message.isEmpty {
      return message
    }

    return nil
  }
}
