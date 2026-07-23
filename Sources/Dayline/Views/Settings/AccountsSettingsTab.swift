import SwiftUI

/// Connected Google, Linear, and GitHub accounts.
struct AccountsSettingsTab: View {
  @EnvironmentObject private var store: StatusStore

  var body: some View {
    Form {
      Section {
        if store.googleAccounts.isEmpty {
          Text("No Google accounts linked")
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.googleAccounts) { status in
            GoogleAccountSettingsRow(status: status)
          }
        }

        Button {
          Task { await store.addGoogleAccount() }
        } label: {
          Label("Add Google Account", systemImage: "plus")
        }
        .disabled(!store.canAddGoogleAccount || !AuthProvider.google.isConfigured)
        .accessibilityIdentifier("settings.account.google.add")

        if store.isGoogleAuthorizationInProgress {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Finish sign-in in your browser.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Button("Cancel") {
              store.cancelConnect(.google)
            }
            .controlSize(.small)
            .accessibilityIdentifier("settings.account.google.cancel")
          }
        } else if let error = store.googleAuthorizationError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.account.google.error")
        }
      } header: {
        Label("Google", systemImage: "calendar")
      }

      if let linearStatus = store.connectionStatuses.first(where: { $0.provider == .linear }) {
        Section {
          LinearAccountSettingsRow(status: linearStatus)
        } header: {
          Label("Linear", systemImage: "checklist")
        }
      }

      if let githubStatus = store.connectionStatuses.first(where: { $0.provider == .github }) {
        Section {
          GitHubAccountSettingsRow(status: githubStatus)
        } header: {
          Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// One linked Google account with an inline calendar picker.
private struct GoogleAccountSettingsRow: View {
  @EnvironmentObject private var store: StatusStore
  @State private var isExpanded = false

  let status: GoogleAccountStatus

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 7) {
        if status.account.calendars.isEmpty {
          Text("Calendars will appear after this account connects.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(status.account.calendars) { calendar in
            Toggle(isOn: calendarBinding(calendar)) {
              HStack(spacing: 6) {
                Text(calendar.name)
                  .lineLimit(1)
                if calendar.isPrimary {
                  Text("Primary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier(
              "settings.account.google.\(status.id.uuidString).calendar.\(calendar.id)"
            )
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 6)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(status.account.label)
            .lineLimit(1)
            .accessibilityIdentifier("settings.account.google.\(status.id.uuidString)")

          if let detail = status.detail, !detail.isEmpty {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          } else {
            Text(calendarCountLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        accountAction

        Button("Disconnect", role: .destructive) {
          Task { await store.disconnectGoogleAccount(status.id) }
        }
        .disabled(store.isGoogleAuthorizationInProgress || status.state == .connecting)
        .accessibilityIdentifier("settings.account.google.\(status.id.uuidString).disconnect")
      }
    }
  }

  @ViewBuilder
  private var accountAction: some View {
    switch status.state {
    case .checking:
      ProgressView()
        .controlSize(.small)
    case .connecting:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Button("Cancel") {
          store.cancelConnect(.google)
        }
        .controlSize(.small)
        .accessibilityIdentifier("settings.account.google.\(status.id.uuidString).cancel")
      }
    case .disconnected:
      Button("Reconnect") {
        Task { await store.reconnectGoogleAccount(status.id) }
      }
      .disabled(store.isGoogleAuthorizationInProgress)
      .accessibilityIdentifier("settings.account.google.\(status.id.uuidString).reconnect")
    case .connected:
      EmptyView()
    }
  }

  private var calendarCountLabel: String {
    let enabledCount = status.account.calendars.filter(\.isEnabled).count
    let totalCount = status.account.calendars.count
    return "\(enabledCount) of \(totalCount) calendars enabled"
  }

  private func calendarBinding(_ calendar: GoogleCalendarSource) -> Binding<Bool> {
    Binding(
      get: { calendar.isEnabled },
      set: {
        store.setGoogleCalendarEnabled(
          accountID: status.id,
          calendarID: calendar.id,
          isEnabled: $0
        )
      }
    )
  }
}

/// Connected Linear workspace with inline team selection.
private struct LinearAccountSettingsRow: View {
  @EnvironmentObject private var store: StatusStore
  @State private var isExpanded = false
  let status: ConnectionStatus

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 7) {
        if let error = store.linearTeamError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.account.linear.teamError")
        }

        if store.linearAccount.teams.isEmpty {
          Text("Teams will appear after this workspace connects.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.linearAccount.teams) { team in
            Toggle(team.label, isOn: teamBinding(team))
              .toggleStyle(.checkbox)
              .accessibilityIdentifier("settings.account.linear.team.\(team.id)")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 6)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(workspaceLabel)
            .lineLimit(1)
          Text(accountDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        if status.state == .checking {
          ProgressView().controlSize(.small)
        } else if status.state == .connecting {
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Button("Cancel") {
              store.cancelConnect(.linear)
            }
            .controlSize(.small)
            .accessibilityIdentifier("settings.account.linear.cancel")
          }
        } else if status.isConnected {
          Button("Disconnect", role: .destructive) { Task { await store.disconnect(.linear) } }
        } else {
          Button("Connect") { Task { await store.connect(.linear) } }
            .disabled(!AuthProvider.linear.isConfigured)
        }
      }
    }
    .accessibilityIdentifier("settings.account.linear")
  }

  private var workspaceLabel: String {
    if !store.linearAccount.workspaceName.isEmpty { return store.linearAccount.workspaceName }
    return status.accountLabel ?? "Linear"
  }

  private var accountDetail: String {
    guard status.isConnected else { return status.detail ?? "Not connected" }
    let total = store.linearAccount.teams.count
    let enabled = store.linearAccount.teams.filter(\.isEnabled).count
    let teamCount = "\(enabled) of \(total) teams enabled"
    guard !store.linearAccount.userLabel.isEmpty else { return teamCount }
    return "\(store.linearAccount.userLabel) · \(teamCount)"
  }

  private func teamBinding(_ team: LinearTeamSelection) -> Binding<Bool> {
    Binding(
      get: { team.isEnabled },
      set: { store.setLinearTeamEnabled(teamID: team.id, isEnabled: $0) }
    )
  }
}

/// Connected GitHub account with inline repository selection.
private struct GitHubAccountSettingsRow: View {
  @EnvironmentObject private var store: StatusStore
  @State private var isExpanded = false
  let status: ConnectionStatus

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 7) {
        if let error = store.githubRepositoryError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.account.github.repositoryError")
        }

        if store.githubAccount.repositories.isEmpty {
          Text("Repositories will appear after this account connects.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.githubAccount.repositories) { repository in
            Toggle(repository.fullName, isOn: repositoryBinding(repository))
              .toggleStyle(.checkbox)
              .accessibilityIdentifier("settings.account.github.repository.\(repository.fullName)")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 6)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(status.accountLabel ?? "GitHub")
            .lineLimit(1)
          Text(repositoryCountLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if status.state == .checking {
          ProgressView().controlSize(.small)
        } else if status.state == .connecting {
          HStack(spacing: 6) {
            if let code = store.githubDeviceUserCode {
              CopyCodeButton(code: code, accessibilityIdentifier: "settings.account.github.copyCode")
                .controlSize(.small)
            }
            ProgressView().controlSize(.small)
            Button("Cancel") {
              store.cancelConnect(.github)
            }
            .controlSize(.small)
            .accessibilityIdentifier("settings.account.github.cancel")
          }
        } else if status.isConnected {
          Button("Disconnect", role: .destructive) { Task { await store.disconnect(.github) } }
        } else {
          Button("Connect") { Task { await store.connect(.github) } }
            .disabled(!AuthProvider.github.isConfigured)
        }
      }
    }
    .accessibilityIdentifier("settings.account.github")
  }

  private var repositoryCountLabel: String {
    let total = store.githubAccount.repositories.count
    let enabled = store.githubAccount.repositories.filter(\.isEnabled).count
    return status.isConnected ? "\(enabled) of \(total) repositories enabled" : (status.detail ?? "Not connected")
  }

  private func repositoryBinding(_ repository: GitHubRepository) -> Binding<Bool> {
    Binding(
      get: { repository.isEnabled },
      set: { store.setGitHubRepositoryEnabled(fullName: repository.fullName, isEnabled: $0) }
    )
  }
}
