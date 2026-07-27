import SwiftUI

/// Startup, refresh, update, feedback, and about settings.
struct GeneralSettingsTab: View {
  @EnvironmentObject private var store: StatusStore
  @EnvironmentObject private var updateService: UpdateService
  @Environment(\.openURL) private var openURL
  @State private var isShowingFeedback = false
  @State private var isExportingDiagnostics = false
  @State private var diagnosticExportStatus: String?
  @State private var diagnosticExportError: String?

  /// Supported refresh cadence choices in minutes.
  private let cadenceOptions = [5, 10, 15, 30, 60]

  var body: some View {
    Form {
      Section {
        Toggle("Launch at login", isOn: launchAtLoginBinding)
          .accessibilityIdentifier("settings.launchAtLogin")

        Picker("Refresh interval", selection: cadenceBinding) {
          ForEach(cadenceOptions, id: \.self) { minutes in
            Text(label(for: minutes)).tag(minutes)
          }
        }
        .accessibilityIdentifier("settings.refreshCadence")
      } header: {
        Label("General", systemImage: "gearshape")
      } footer: {
        if let launchAtLoginError = store.launchAtLoginError {
          Text(launchAtLoginError)
            .accessibilityIdentifier("settings.launchAtLoginError")
        }
      }

      Section {
        Toggle("Install updates automatically", isOn: automaticUpdatesBinding)
          .disabled(!updateService.isUpdaterAvailable)
          .accessibilityIdentifier("settings.automaticUpdates")

        Button("Check for Updates...") {
          updateService.checkForUpdates()
        }
        .disabled(!updateService.canCheckForUpdates)
        .accessibilityIdentifier("settings.checkForUpdates")
      } header: {
        Label("Updates", systemImage: "arrow.triangle.2.circlepath")
      }

      Section {
        Button("Submit Feedback...") {
          isShowingFeedback = true
        }
        .accessibilityIdentifier("settings.submitFeedback")

        Button("Export Diagnostics...") {
          Task { await exportDiagnostics() }
        }
        .disabled(isExportingDiagnostics)
        .accessibilityIdentifier("settings.exportDiagnostics")

        if let diagnosticExportStatus {
          Text(diagnosticExportStatus)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("settings.diagnosticExportStatus")
        }

        if let diagnosticExportError {
          Text(diagnosticExportError)
            .foregroundStyle(.red)
            .accessibilityIdentifier("settings.diagnosticExportError")
        }
      } header: {
        Label("Feedback and Diagnostics", systemImage: "text.bubble")
      } footer: {
        Text("Feedback is submitted anonymously as a public GitHub issue. Manual diagnostic exports stay local; diagnostics are uploaded only when you explicitly include them with feedback.")
      }

      Section {
        LabeledContent("Version", value: versionLabel)
          .accessibilityIdentifier("settings.version")

        Button("View Changelog...") {
          openURL(URL(string: "https://dayline.robin.build/changelog")!)
        }
        .accessibilityIdentifier("settings.viewChangelog")
      } header: {
        Label("About", systemImage: "info.circle")
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(isPresented: $isShowingFeedback) {
      FeedbackView()
    }
    .onAppear {
      store.refreshLaunchAtLoginStatus()
    }
  }

  /// Marketing version plus build number from the bundle, when present.
  private var versionLabel: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String
    let build = info?["CFBundleVersion"] as? String
    switch (version, build) {
    case let (version?, build?):
      return "\(version) (\(build))"
    case let (version?, nil):
      return version
    default:
      return "Unknown"
    }
  }

  /// Binding that forwards launch-at-login changes to the store.
  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { store.launchAtLoginEnabled },
      set: { store.setLaunchAtLoginEnabled($0) }
    )
  }

  /// Binding that persists the automatic-update preference.
  private var automaticUpdatesBinding: Binding<Bool> {
    Binding(
      get: { updateService.automaticallyInstallsUpdates },
      set: { updateService.setAutomaticallyInstallsUpdates($0) }
    )
  }

  /// Binding that forwards settings changes to the store.
  private var cadenceBinding: Binding<Int> {
    Binding(
      get: { store.refreshIntervalMinutes },
      set: { store.setRefreshInterval(minutes: $0) }
    )
  }

  /// Returns the menu label for a cadence option.
  private func label(for minutes: Int) -> String {
    minutes == 60 ? "Every hour" : "Every \(minutes) minutes"
  }

  @MainActor
  private func exportDiagnostics() async {
    guard !isExportingDiagnostics else {
      return
    }
    isExportingDiagnostics = true
    defer { isExportingDiagnostics = false }

    diagnosticExportStatus = nil
    diagnosticExportError = nil
    do {
      if let destination = try await DiagnosticsExporter().export() {
        diagnosticExportStatus = "Saved \(destination.lastPathComponent)"
      }
    } catch {
      diagnosticExportError = error.localizedDescription
      DaylineDiagnostics.record("Diagnostic export failed", category: .feedback)
    }
  }
}
