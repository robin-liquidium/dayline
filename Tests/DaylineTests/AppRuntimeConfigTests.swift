import Testing
@testable import Dayline

struct AppRuntimeConfigTests {
  @Test func configuredStorageNamespaceUsesNonEmptyBundleValue() {
    #expect(AppRuntimeConfig.configuredString("Dayline Dev", fallback: "Dayline") == "Dayline Dev")
  }

  @Test func configuredStorageNamespacePreservesShippedFallback() {
    #expect(AppRuntimeConfig.configuredString(nil, fallback: "Dayline") == "Dayline")
    #expect(AppRuntimeConfig.configuredString("  ", fallback: "Dayline") == "Dayline")
  }
}
