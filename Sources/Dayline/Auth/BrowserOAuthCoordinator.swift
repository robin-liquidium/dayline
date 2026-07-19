import AppKit
import Foundation
import os

/// Opens the default browser for OAuth and completes when the app receives the redirect URL.
@MainActor
final class BrowserOAuthCoordinator {
  /// Shared coordinator used by all providers.
  static let shared = BrowserOAuthCoordinator()

  /// Logger for OAuth browser flow diagnostics.
  private let logger = Logger(subsystem: "build.local.Dayline", category: "oauth")

  /// In-flight browser authorization waiting for a redirect.
  private var pending: PendingAuthorization?

  /// Opens the provider authorization page and awaits the custom-scheme callback.
  func authenticate(url: URL, redirectURI: String) async throws -> URL {
    if let existing = pending {
      existing.continuation.resume(throwing: OAuthError.authorizationCancelled)
      pending = nil
    }

    let attemptID = UUID()
    guard let redirectURL = URL(string: redirectURI) else {
      throw OAuthError.invalidCallback
    }
    logger.info("Opening browser OAuth for scheme \(redirectURL.scheme ?? "", privacy: .public)")

    return try await withCheckedThrowingContinuation { continuation in
      pending = PendingAuthorization(
        id: attemptID,
        callbackScheme: redirectURL.scheme?.lowercased() ?? "",
        callbackHost: redirectURL.host?.lowercased(),
        callbackPath: redirectURL.path,
        continuation: continuation
      )

      let opened = NSWorkspace.shared.open(url)
      guard opened else {
        pending = nil
        continuation.resume(throwing: OAuthError.authorizationFailed("Could not open the default browser."))
        return
      }

      Task { @MainActor in
        try? await Task.sleep(for: .seconds(300))
        guard let pending = self.pending, pending.id == attemptID else {
          return
        }
        self.pending = nil
        pending.continuation.resume(throwing: OAuthError.authorizationFailed("Sign-in timed out. Try Connect again."))
      }
    }
  }

  /// Handles an incoming custom-scheme URL from the browser redirect.
  @discardableResult
  func handleOpenURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
          let pending,
          scheme == pending.callbackScheme,
          url.host?.lowercased() == pending.callbackHost,
          url.path == pending.callbackPath else {
      return false
    }

    logger.info("Received OAuth callback for scheme \(scheme, privacy: .public)")
    self.pending = nil
    pending.continuation.resume(returning: url)
    return true
  }

  /// Cancels any in-flight browser authorization.
  func cancel() {
    guard let pending else {
      return
    }
    self.pending = nil
    pending.continuation.resume(throwing: OAuthError.authorizationCancelled)
  }
}

/// One browser authorization attempt waiting for its redirect.
private struct PendingAuthorization {
  /// Stable identity for this attempt, used to ignore stale timeouts.
  let id: UUID

  /// Expected callback URL scheme, lowercased.
  let callbackScheme: String

  /// Expected callback host, lowercased when present.
  let callbackHost: String?

  /// Expected callback path.
  let callbackPath: String

  /// Continuation resumed when the redirect arrives or the attempt fails.
  let continuation: CheckedContinuation<URL, Error>
}
