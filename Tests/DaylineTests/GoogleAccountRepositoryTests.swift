import Foundation
import Testing
@testable import Dayline

struct GoogleAccountRepositoryTests {
  @Test func legacyMigrationWritesScopedCredentialsBeforeDeletingLegacyAndIsIdempotent() throws {
    let suiteName = "GoogleAccountRepositoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let credentials = MemoryCredentialStore()
    let legacyTokens = Data("legacy-token-bundle".utf8)
    credentials.entries[GoogleAccountRepository.legacyCredentialAccount] = legacyTokens
    let repository = GoogleAccountRepository(defaults: defaults, credentials: credentials)
    credentials.beforeDelete = { account in
      guard account == GoogleAccountRepository.legacyCredentialAccount else { return }
      #expect(defaults.data(forKey: GoogleAccountRepository.defaultsKey) != nil)
    }

    let migrated = try repository.loadAndMigrateLegacyAccount()

    let account = try #require(migrated.first)
    #expect(migrated.count == 1)
    #expect(credentials.entries[account.credentialAccount] == legacyTokens)
    #expect(credentials.entries[GoogleAccountRepository.legacyCredentialAccount] == nil)
    #expect(credentials.operations == [
      "save:\(account.credentialAccount)",
      "delete:\(GoogleAccountRepository.legacyCredentialAccount)"
    ])

    let loadedAgain = try repository.loadAndMigrateLegacyAccount()
    #expect(loadedAgain == migrated)
    #expect(credentials.operations.count == 2)
  }

  @Test func legacyMigrationReturnsCommittedAccountWhenCleanupFails() throws {
    let suiteName = "GoogleAccountRepositoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let credentials = MemoryCredentialStore()
    let legacyTokens = Data("legacy-token-bundle".utf8)
    credentials.entries[GoogleAccountRepository.legacyCredentialAccount] = legacyTokens
    credentials.failLegacyDeletion = true
    let repository = GoogleAccountRepository(defaults: defaults, credentials: credentials)

    let migrated = try repository.loadAndMigrateLegacyAccount()
    let account = try #require(migrated.first)

    #expect(credentials.entries[account.credentialAccount] == legacyTokens)
    #expect(credentials.entries[GoogleAccountRepository.legacyCredentialAccount] == legacyTokens)
    #expect(try repository.load() == migrated)

    credentials.failLegacyDeletion = false
    #expect(try repository.loadAndMigrateLegacyAccount() == migrated)
    #expect(credentials.entries[GoogleAccountRepository.legacyCredentialAccount] == nil)
  }

  @Test func completedLegacyMigrationDoesNotDuplicateAnAccountAfterIdentityDiscovery() throws {
    let suiteName = "GoogleAccountRepositoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let credentials = MemoryCredentialStore()
    credentials.entries[GoogleAccountRepository.legacyCredentialAccount] = Data("legacy-token-bundle".utf8)
    credentials.failLegacyDeletion = true
    let repository = GoogleAccountRepository(defaults: defaults, credentials: credentials)

    var migrated = try repository.loadAndMigrateLegacyAccount()
    migrated[0].providerAccountID = "robin@example.com"
    migrated[0].displayLabel = "robin@example.com"
    try repository.save(migrated)

    let loadedAgain = try repository.loadAndMigrateLegacyAccount()

    #expect(loadedAgain == migrated)
    #expect(loadedAgain.count == 1)
  }
}

private final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
  var entries: [String: Data] = [:]
  var operations: [String] = []
  var beforeDelete: ((String) -> Void)?
  var failLegacyDeletion = false

  func data(for account: String) throws -> Data? {
    entries[account]
  }

  func save(_ data: Data, for account: String) throws {
    operations.append("save:\(account)")
    entries[account] = data
  }

  func delete(account: String) throws {
    beforeDelete?(account)
    operations.append("delete:\(account)")
    if failLegacyDeletion && account == GoogleAccountRepository.legacyCredentialAccount {
      throw TestCredentialStoreError.deletionFailed
    }
    entries[account] = nil
  }
}

private enum TestCredentialStoreError: Error {
  case deletionFailed
}
