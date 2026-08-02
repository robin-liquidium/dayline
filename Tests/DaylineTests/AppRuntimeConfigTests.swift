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

  @Test func authoritativeOAuthConfigurationIgnoresInheritedEnvironment() {
    #expect(AuthConfig.configuredValue(
      environmentValue: "production-client",
      bundleValue: "dev-client",
      fallback: "fallback-client",
      bundleIsAuthoritative: true
    ) == "dev-client")
    #expect(AuthConfig.configuredValue(
      environmentValue: "production-client",
      bundleValue: nil,
      fallback: "fallback-client",
      bundleIsAuthoritative: true
    ).isEmpty)
  }

  @Test func productionOAuthConfigurationPreservesEnvironmentOverride() {
    #expect(AuthConfig.configuredValue(
      environmentValue: "custom-client",
      bundleValue: "bundled-client",
      fallback: "fallback-client",
      bundleIsAuthoritative: false
    ) == "custom-client")
  }
}
