import Foundation
import Security

/// Storage contract used by OAuth sessions and account migration.
protocol CredentialStore: Sendable {
  func data(for account: String) throws -> Data?
  func save(_ data: Data, for account: String) throws
  func delete(account: String) throws
}

/// Failure cases surfaced by Keychain operations.
enum KeychainStoreError: LocalizedError {
  /// SecItem API returned an unexpected status.
  case unhandled(OSStatus)

  /// Human-readable error text.
  var errorDescription: String? {
    switch self {
    case .unhandled(let status):
      "Keychain operation failed (\(status))."
    }
  }
}

/// Minimal generic-password Keychain store used for OAuth token bundles.
struct KeychainStore: CredentialStore {
  /// Service namespacing all Dayline Keychain items.
  let service: String

  /// Loads raw item data for one account, or `nil` when nothing is stored.
  func data(for account: String) throws -> Data? {
    var query = baseQuery(for: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    switch status {
    case errSecSuccess:
      return item as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainStoreError.unhandled(status)
    }
  }

  /// Inserts or replaces raw item data for one account.
  func save(_ data: Data, for account: String) throws {
    let query = baseQuery(for: account)
    let attributes = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var newItem = query
      newItem[kSecValueData as String] = data
      newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let addStatus = SecItemAdd(newItem as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainStoreError.unhandled(addStatus)
      }
    default:
      throw KeychainStoreError.unhandled(status)
    }
  }

  /// Removes the item for one account, ignoring missing items.
  func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unhandled(status)
    }
  }

  /// Base query selecting one generic-password item.
  private func baseQuery(for account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}
