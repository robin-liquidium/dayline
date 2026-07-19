import Foundation
import Testing
@testable import Dayline

struct OAuthSessionTests {
  @Test func installedCredentialsCanBeTransferredAndDiscarded() async throws {
    let credentials = OAuthSessionMemoryCredentialStore()
    let session = OAuthSession(
      provider: .google,
      credentials: credentials,
      credentialAccount: "google.pending.test"
    )
    let tokens = OAuthTokens(
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: Date().addingTimeInterval(3_600),
      scope: "calendar.readonly"
    )

    try await session.install(tokens)
    let transferred = try await session.currentTokens()

    #expect(transferred?.accessToken == "access")
    #expect(transferred?.refreshToken == "refresh")
    #expect(credentials.entries["google.pending.test"] != nil)

    await session.discardCredentials()

    #expect(credentials.entries["google.pending.test"] == nil)
    #expect(await session.hasTokens() == false)
  }
}

private final class OAuthSessionMemoryCredentialStore: CredentialStore, @unchecked Sendable {
  var entries: [String: Data] = [:]

  func data(for account: String) throws -> Data? {
    entries[account]
  }

  func save(_ data: Data, for account: String) throws {
    entries[account] = data
  }

  func delete(account: String) throws {
    entries[account] = nil
  }
}
