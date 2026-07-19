import Foundation

/// Persists non-secret Google account metadata and migrates the legacy singleton token.
struct GoogleAccountRepository {
  static let defaultsKey = "googleAccounts"
  static let legacyCredentialAccount = "google"
  static let legacyMigrationCompletedKey = "googleAccounts.legacyMigrationCompleted"

  let defaults: UserDefaults
  let credentials: any CredentialStore

  init(
    defaults: UserDefaults = .standard,
    credentials: any CredentialStore = KeychainStore(service: "build.local.Dayline.oauth")
  ) {
    self.defaults = defaults
    self.credentials = credentials
  }

  /// Loads saved accounts and safely adopts an existing pre-multi-account token bundle.
  func loadAndMigrateLegacyAccount() throws -> [GoogleAccount] {
    var accounts = try load()
    guard let legacyTokens = try credentials.data(for: Self.legacyCredentialAccount) else {
      return accounts
    }

    if defaults.bool(forKey: Self.legacyMigrationCompletedKey) {
      try? credentials.delete(account: Self.legacyCredentialAccount)
      return accounts
    }

    // If a previous migration saved metadata but crashed before deleting the old item,
    // deleting it now avoids creating a duplicate account.
    if accounts.contains(where: { $0.providerAccountID == nil }) {
      defaults.set(true, forKey: Self.legacyMigrationCompletedKey)
      try? credentials.delete(account: Self.legacyCredentialAccount)
      return accounts
    }

    let account = GoogleAccount(
      id: UUID(),
      providerAccountID: nil,
      displayLabel: nil,
      calendars: []
    )

    // Credentials first, metadata second, legacy deletion last. A failed write never
    // destroys the only usable copy of the user's existing Google authorization.
    try credentials.save(legacyTokens, for: account.credentialAccount)
    accounts.append(account)
    try save(accounts)
    defaults.set(true, forKey: Self.legacyMigrationCompletedKey)
    try? credentials.delete(account: Self.legacyCredentialAccount)
    return accounts
  }

  /// Loads account metadata from local preferences.
  func load() throws -> [GoogleAccount] {
    guard let data = defaults.data(forKey: Self.defaultsKey) else {
      return []
    }
    return try JSONDecoder().decode([GoogleAccount].self, from: data)
  }

  /// Replaces all persisted account metadata.
  func save(_ accounts: [GoogleAccount]) throws {
    let data = try JSONEncoder().encode(accounts)
    defaults.set(data, forKey: Self.defaultsKey)
  }
}
