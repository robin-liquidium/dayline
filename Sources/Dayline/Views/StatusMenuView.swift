import AppKit
import SwiftUI

/// Shared row height for compact Linear and Notes rows.
private let workItemRowHeight: CGFloat = 46

/// Row height for calendar event rows showing their source calendar.
private let eventRowHeight: CGFloat = 48

/// Compact row height for calendar event rows without a source calendar label.
private let compactEventRowHeight: CGFloat = 36

/// Width of the trailing swipe reveal lane for destructive row actions.
private let destructiveRevealWidth: CGFloat = 52

/// Diameter of the compact destructive row action.
private let destructiveButtonSize: CGFloat = 30

/// Popover content shown when the user opens the menu bar extra.
struct StatusMenuView: View {
  @EnvironmentObject private var store: StatusStore
  @EnvironmentObject private var updateService: UpdateService
  @Environment(\.openWindow) private var openWindow
  @FocusState private var isKeyboardTargetFocused: Bool

  /// Builds the compact menu bar popover content.
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerBar
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if store.hasConnectionSetupItems {
            ConnectionSetupSection(
              statuses: store.connectionSetupItems,
              googleAccounts: store.googleAccountsNeedingAttention
            )
          }

          if store.isCalendarSectionVisible {
            CalendarSection(
              events: store.events,
              tomorrowEvents: store.tomorrowEvents,
              warnings: store.calendarWarnings,
              hoveredEventID: store.hoveredEventID,
              isTomorrowExpanded: store.isTomorrowExpanded,
              now: store.calendarHighlightDate
            )
          }
          if store.isIssuesSectionVisible, let activeSource = store.activeIssueSource {
            IssuesSection(
              activeSource: activeSource,
              openNewIssue: { openLinearIssueCreator() },
              openNewGitHubIssue: { openGitHubIssueCreator() }
            )
          }

          if store.showsNotesSection {
            NotesSection(
              notes: store.notes,
              error: store.notesError,
              hoveredNoteID: store.hoveredNoteID,
              openNewNote: {
                openNoteEditor(.new)
              },
              openNote: { note in
                openNoteEditor(.existing(note.id))
              }
            )
          }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)
      .frame(height: scrollContentHeight)
      .clipped()
      footerBar
    }
    .frame(width: 400)
    .focusable()
    .focusEffectDisabled()
    .focused($isKeyboardTargetFocused)
    .onAppear {
      isKeyboardTargetFocused = true
    }
    .onKeyPress { keyPress in
      handleKeyPress(keyPress.characters) ? .handled : .ignored
    }
  }

  /// Header row with title, freshness, and refresh action.
  private var header: some View {
    HStack(spacing: 10) {
      DaylineWordmark()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Dayline")

      Spacer()

      Text(DisplayFormatters.lastUpdated(store.lastUpdatedAt))
        .font(.caption)
        .foregroundStyle(.secondary)

      Button {
        Task { await store.refresh() }
      } label: {
        Image(systemName: store.isRefreshing ? "clock.arrow.circlepath" : "arrow.clockwise")
          .padding(6)
          .contentShape(Rectangle())
          .hoverHighlight(isHovered: store.hoveredControlID == .refresh, isEnabled: !store.isRefreshing)
      }
      .buttonStyle(.plain)
      .help("Refresh")
      .accessibilityLabel("Refresh")
      .accessibilityHint("Refresh calendar events and Linear issues")
      .accessibilityIdentifier("dayline.refresh")
      .disabled(store.isRefreshing)
      .onHover { isHovered in
        store.setHoveredControl(isHovered ? .refresh : nil)
      }
    }
  }

  /// Header wrapper that stays above scrolling content.
  private var headerBar: some View {
    header
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Footer row with settings, update, and quit actions.
  private var footer: some View {
    ZStack {
      HStack {
        Button {
          openWindow(id: "settings")
          SettingsWindowPresenter.bringSettingsToFront()
        } label: {
          Label("Settings", systemImage: "gearshape")
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .hoverHighlight(isHovered: store.hoveredControlID == .settings)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Open Dayline settings")
        .accessibilityIdentifier("dayline.settings")
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .settings : nil)
        }

        Spacer()

        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Label("Quit", systemImage: "power")
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .hoverHighlight(isHovered: store.hoveredControlID == .quit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quit")
        .accessibilityHint("Quit Dayline")
        .accessibilityIdentifier("dayline.quit")
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .quit : nil)
        }
      }

      if let availableUpdateVersion = updateService.availableVersion {
        Button {
          updateService.performUpdate()
        } label: {
          Label("Update", systemImage: "arrow.down.circle")
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .hoverHighlight(isHovered: store.hoveredControlID == .update)
        }
        .buttonStyle(.plain)
        .help("Download and install Dayline \(availableUpdateVersion)")
        .accessibilityLabel("Update Dayline")
        .accessibilityHint("Download and install version \(availableUpdateVersion)")
        .accessibilityIdentifier("dayline.update")
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .update : nil)
        }
      }
    }
  }

  /// Footer wrapper that stays above scrolling content.
  private var footerBar: some View {
    footer
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Estimated scroll viewport height, capped so expanded issues scroll.
  private var scrollContentHeight: CGFloat {
    min(max(estimatedContentHeight, 220), 620)
  }

  /// Lightweight estimate that keeps the initial menu compact before expansion.
  private var estimatedContentHeight: CGFloat {
    let setupItemCount = store.connectionSetupItems.count + store.googleAccountsNeedingAttention.count
    let setupRows = store.hasConnectionSetupItems ? CGFloat(max(setupItemCount, 1)) * 64 + 44 : 0
    let eventRowEstimate: CGFloat = store.showsCalendarSourceNames ? 48 : compactEventRowHeight
    let eventRows = store.isCalendarSectionVisible ? CGFloat(max(store.events.count, 1)) * eventRowEstimate : 0
    let tomorrowRows = store.isCalendarSectionVisible && store.isTomorrowExpanded
      ? CGFloat(max(store.tomorrowEvents.count, 1)) * eventRowEstimate + 34 : 0
    let bothIssueSourcesAvailable = store.availableIssueSources.count > 1
    let visibleIssueCount = bothIssueSourcesAvailable
      ? max(store.issues.count, store.githubIssues.count)
      : (store.activeIssueSource == .github ? store.githubIssues.count : store.issues.count)
    let issueRows = store.isIssuesSectionVisible ? CGFloat(max(visibleIssueCount, 1)) * workItemRowHeight : 0
    let issueMoreRow: CGFloat = store.isIssuesSectionVisible && store.availableIssueSources.contains(.linear) && (store.hasMoreIssues || store.hasExpandedIssues) ? 34 : 0
    let noteRows = store.showsNotesSection ? CGFloat(max(store.notes.count, 1)) * workItemRowHeight : 0
    let noteMoreRow: CGFloat = store.showsNotesSection && (store.hasMoreNotes || store.hasExpandedNotes) ? 34 : 0
    return 108 + setupRows + eventRows + tomorrowRows + issueRows + issueMoreRow + noteRows + noteMoreRow
  }

  /// Handles menu-level keyboard shortcuts.
  private func handleKeyPress(_ characters: String) -> Bool {
    if store.matchesStatusPickerHotkey(characters) {
      return store.presentStatusPickerForHoveredIssue()
    }

    if store.matchesPriorityPickerHotkey(characters) {
      return store.presentPriorityPickerForHoveredIssue()
    }

    if store.matchesDueDatePickerHotkey(characters) {
      return store.presentDueDatePickerForHoveredIssue()
    }

    if store.matchesLabelPickerHotkey(characters) {
      return store.presentLabelPickerForHoveredIssue()
    }

    if store.matchesAssigneePickerHotkey(characters) {
      return store.presentAssigneePickerForHoveredIssue()
    }

    if store.matchesCopyIssueHotkey(characters) {
      return store.copyHoveredIssueLink() || store.copyHoveredEventLink()
    }

    return false
  }

  /// Opens a note editor window and brings the accessory app forward.
  private func openNoteEditor(_ request: NoteEditorRequest) {
    openWindow(value: request)
    NoteEditorWindowPresenter.bringNoteWindowToFront()
  }

  /// Opens the Linear issue creator window and brings the accessory app forward.
  private func openLinearIssueCreator() {
    openWindow(id: "linearIssueCreator")
    LinearIssueEditorWindowPresenter.bringIssueWindowToFront()
  }

  /// Opens the GitHub issue creator window and brings the accessory app forward.
  private func openGitHubIssueCreator() {
    openWindow(id: "githubIssueCreator")
    GitHubIssueEditorWindowPresenter.bringIssueWindowToFront()
  }
}

/// Small icon button that hides one provider's setup prompt and menu content.
private struct DismissProviderButton: View {
  @EnvironmentObject private var store: StatusStore
  @State private var isHovered = false

  /// Provider dismissed when the button is pressed.
  let provider: AuthProvider

  var body: some View {
    Button {
      store.dismissProvider(provider)
    } label: {
      Image(systemName: "xmark")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(5)
        .contentShape(Rectangle())
        .hoverHighlight(isHovered: isHovered)
    }
    .buttonStyle(.plain)
    .help("Hide \(provider.title) from the menu")
    .accessibilityLabel("Dismiss \(provider.title)")
    .accessibilityHint("Hides \(provider.title) from the menu until you connect it from Settings")
    .accessibilityIdentifier("setup.\(provider.id).dismiss")
    .onHover { isHovered = $0 }
  }
}

/// Issues section with a tab switcher when both providers are connected.
private struct IssuesSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Issue source currently displayed.
  let activeSource: IssueSource

  /// Action run when the user creates a new Linear issue.
  let openNewIssue: () -> Void

  /// Action run when the user creates a new GitHub issue.
  let openNewGitHubIssue: () -> Void

  /// Builds the issues section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        if store.availableIssueSources.count > 1 {
          IssueSourceTabSwitcher(activeSource: activeSource)
        } else {
          SectionTitle(title: activeSource.label)
        }

        Spacer(minLength: 0)

        if activeSource == .linear {
          newIssueButton(
            action: openNewIssue,
            controlID: .newLinearIssue,
            help: "New Linear issue",
            identifier: "linear.new"
          )
        } else {
          newIssueButton(
            action: openNewGitHubIssue,
            controlID: .newGitHubIssue,
            help: "New GitHub issue",
            identifier: "github.new"
          )
        }
      }

      ZStack(alignment: .topLeading) {
        if activeSource == .github {
          GitHubSection(
            issues: store.githubIssues,
            error: store.githubError,
            hoveredIssueTarget: store.hoveredIssueTarget,
            copiedIssueTarget: store.copiedIssueTarget
          )
          .transition(.opacity)
        } else {
          LinearSection(
            issues: store.issues,
            error: store.linearError,
            hoveredIssueTarget: store.hoveredIssueTarget,
            copiedIssueTarget: store.copiedIssueTarget,
            updatingIssueTarget: store.updatingIssueTarget,
            updatingPriorityIssueID: store.updatingPriorityIssueID,
            updatingDueDateIssueID: store.updatingDueDateIssueID
          )
          .transition(.opacity)
        }
      }
    }
    .animation(.smooth(duration: 0.2), value: activeSource)
  }

  /// Plus button that opens the issue creator for the active source.
  private func newIssueButton(
    action: @escaping () -> Void,
    controlID: MenuControlID,
    help: String,
    identifier: String
  ) -> some View {
    Button(action: action) {
      Image(systemName: "plus")
        .padding(5)
        .contentShape(Rectangle())
        .hoverHighlight(isHovered: store.hoveredControlID == controlID)
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
    .accessibilityHint("Create an issue")
    .accessibilityIdentifier(identifier)
    .onHover { isHovered in
      store.setHoveredControl(isHovered ? controlID : nil)
    }
  }
}

/// Spinner row shown in an issue section while a refresh is in flight.
private struct LoadingIssuesRow: View {
  var body: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("Loading issues...")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Loading issues")
    .accessibilityIdentifier("issues.loading")
  }
}

/// Liquid Glass switcher between connected issue providers.
private struct IssueSourceTabSwitcher: View {
  @EnvironmentObject private var store: StatusStore
  @Namespace private var selectionGlass

  /// Issue source currently displayed.
  let activeSource: IssueSource

  var body: some View {
    ZStack {
      pillLayer
      segmentButtons
    }
    .padding(2)
    .background {
      Capsule(style: .continuous)
        .fill(Color.primary.opacity(0.05))
    }
  }

  /// Hidden layout replicas that carry the glass selection pill as it slides between segments.
  private var pillLayer: some View {
    GlassEffectContainer(spacing: 2) {
      HStack(spacing: 2) {
        ForEach(store.availableIssueSources) { source in
          segmentLabel(for: source)
            .hidden()
            .background {
              if source == activeSource {
                Color.clear
                  .glassEffect(.regular.interactive(), in: .capsule)
                  .matchedGeometryEffect(id: "selection", in: selectionGlass)
              }
            }
        }
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  /// Visible, static segment labels that handle taps above the sliding pill.
  private var segmentButtons: some View {
    HStack(spacing: 2) {
      ForEach(store.availableIssueSources) { source in
        Button {
          withAnimation(.smooth(duration: 0.25)) {
            store.setIssueSource(source)
          }
        } label: {
          segmentLabel(for: source)
            .foregroundStyle(source == activeSource ? .primary : .secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(source.label) issues")
        .accessibilityAddTraits(source == activeSource ? [.isSelected] : [])
        .accessibilityIdentifier("issues.source.\(source.id)")
      }
    }
  }

  /// Shared label metrics so the pill layer and the button layer stay aligned.
  private func segmentLabel(for source: IssueSource) -> some View {
    Text(source.label)
      .font(.caption.weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
  }
}

/// Setup section shown when Google or Linear accounts are not connected.
private struct ConnectionSetupSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Connection statuses that need user attention.
  let statuses: [ConnectionStatus]

  /// Existing Google accounts that need account-specific reauthentication.
  let googleAccounts: [GoogleAccountStatus]

  /// Builds the setup section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionTitle(title: "Setup")

        Spacer(minLength: 0)

        Button {
          Task { await store.refreshConnectionStatus() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Check again")
        .accessibilityLabel("Check account connections again")
        .accessibilityIdentifier("setup.checkAgain")
      }

      VStack(alignment: .leading, spacing: 8) {
        ForEach(statuses) { status in
          ConnectionSetupRow(status: status)
        }
        ForEach(googleAccounts) { status in
          GoogleAccountSetupRow(status: status)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Setup row that reconnects one affected Google account without touching others.
private struct GoogleAccountSetupRow: View {
  @EnvironmentObject private var store: StatusStore

  let status: GoogleAccountStatus

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: "person.crop.circle.badge.exclamationmark")
        .font(.callout.weight(.semibold))
        .foregroundStyle(.yellow)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text("Reconnect \(status.account.label)")
          .font(.callout.weight(.medium))
          .foregroundStyle(.primary)

        if let detail = status.detail, !detail.isEmpty {
          Text(detail.compactLine(limit: 78))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 8)

      if status.state == .connecting {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)

          Button("Cancel") {
            store.cancelConnect(.google)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("setup.google.\(status.id.uuidString).cancel")
        }
      } else {
        HStack(spacing: 2) {
          Button("Reconnect") {
            Task { await store.reconnectGoogleAccount(status.id) }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(store.isGoogleAuthorizationInProgress)
          .accessibilityIdentifier("setup.google.\(status.id.uuidString).reconnect")

          DismissProviderButton(provider: .google)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 7)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.05))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("setup.google.\(status.id.uuidString)")
  }
}

/// One setup row for an external account connection.
private struct ConnectionSetupRow: View {
  @EnvironmentObject private var store: StatusStore

  /// Connection status represented by the row.
  let status: ConnectionStatus

  /// Builds the setup row.
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: systemImage)
        .font(.callout.weight(.semibold))
        .foregroundStyle(iconColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text(status.title)
          .font(.callout.weight(.medium))
          .foregroundStyle(.primary)

        if let detail = status.detail, !detail.isEmpty {
          Text(detail.compactLine(limit: 78))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 8)

      actionButton
    }
    .padding(.leading, 16)
    .padding(.trailing, 11)
    .padding(.vertical, 7)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.05))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("setup.\(status.provider.id)")
  }

  /// Action button appropriate for the connection state.
  @ViewBuilder
  private var actionButton: some View {
    switch status.state {
    case .checking:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Checking")
    case .connecting:
      HStack(spacing: 6) {
        if status.provider == .github, let code = store.githubDeviceUserCode {
          CopyCodeButton(code: code, accessibilityIdentifier: "setup.\(status.provider.id).copyCode")
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Connecting")

        Button("Cancel") {
          store.cancelConnect(status.provider)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("setup.\(status.provider.id).cancel")
      }
    case .disconnected:
      HStack(spacing: 2) {
        Button("Connect") {
          Task { await store.connect(status.provider) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!status.provider.isConfigured)
        .accessibilityIdentifier("setup.\(status.provider.id).connect")

        DismissProviderButton(provider: status.provider)
      }
    case .connected:
      EmptyView()
    }
  }

  /// Symbol for the current connection state.
  private var systemImage: String {
    switch status.state {
    case .checking:
      "clock.arrow.circlepath"
    case .disconnected:
      "person.crop.circle.badge.exclamationmark"
    case .connecting:
      "arrow.triangle.2.circlepath"
    case .connected:
      "checkmark.circle.fill"
    }
  }

  /// Color for the current connection state symbol.
  private var iconColor: Color {
    switch status.state {
    case .checking:
      .secondary
    case .disconnected:
      .yellow
    case .connecting:
      .blue
    case .connected:
      .green
    }
  }
}

/// One selectable option row with the menu's standard subtle hover background.
private struct PickerOptionRow<Content: View>: View {
  @State private var isHovered = false

  /// Whether the row is currently disabled.
  let isDisabled: Bool

  /// Action run when the row is pressed.
  let action: () -> Void

  /// Row label content.
  @ViewBuilder let content: Content

  /// Builds the option row.
  var body: some View {
    Button(action: action) {
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background {
      if isHovered && !isDisabled {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.primary.opacity(0.06))
      }
    }
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .onHover { isHovered = $0 }
  }
}

/// Shared checkbox picker for provider-specific labels or assignees.
private struct IssueMultiValuePickerPopover: View {
  enum Kind { case labels, assignees }

  @EnvironmentObject private var store: StatusStore
  let target: IssueActionTarget
  let title: String
  let kind: Kind
  @State private var labels: [IssueLabelOption] = []
  @State private var assignees: [IssueAssigneeOption] = []
  @State private var error: String?
  @State private var isLoading = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(pickerTitle)
        .font(.headline)
      Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
      Divider()
      if let error {
        Text(error).font(.caption).foregroundStyle(.secondary)
      } else if isLoading {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
      } else if labels.isEmpty && assignees.isEmpty {
        Text(kind == .labels ? "No labels available" : "No assignees available")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if kind == .labels {
              ForEach(labels) { option in
                let isSelected = store.selectedLabelIDs(for: target).contains(option.id)
                PickerOptionRow(isDisabled: store.updatingIssueTarget == target) {
                  Task { await store.toggleLabel(target: target, option: option) }
                } content: {
                  HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                      .foregroundStyle(Color(linearHex: option.color))
                    Text(option.name)
                    Spacer(minLength: 0)
                    if isSelected {
                      Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                .accessibilityIdentifier("issue.label.\(option.id)")
              }
            } else {
              ForEach(assignees) { option in
                let isSelected = store.selectedAssigneeIDs(for: target).contains(option.id)
                PickerOptionRow(isDisabled: store.updatingIssueTarget == target) {
                  Task { await store.toggleAssignee(target: target, option: option) }
                } content: {
                  HStack(spacing: 8) {
                    Image(systemName: "person")
                      .foregroundStyle(.secondary)
                    Text(option.name)
                    Spacer(minLength: 0)
                    if isSelected {
                      Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                .accessibilityIdentifier("issue.assignee.\(option.id)")
              }
            }
          }
        }
        .frame(height: min(CGFloat(optionCount) * 32, 280))
      }
    }
    .padding(12)
    .frame(width: 250)
    .task {
      defer { isLoading = false }
      do {
        if kind == .labels { labels = try await store.labelOptions(for: target) }
        else { assignees = try await store.assigneeOptions(for: target) }
      } catch { self.error = error.localizedDescription }
    }
  }

  private var pickerTitle: String {
    if kind == .labels { return "Change Labels" }
    if case .linear = target { return "Change Assignee" }
    return "Change Assignees"
  }

  private var optionCount: Int {
    kind == .labels ? labels.count : assignees.count
  }
}

/// Compact status selector for GitHub's open/closed states.
private struct GitHubStatusPickerPopover: View {
  @EnvironmentObject private var store: StatusStore
  let issue: GitHubIssueItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Change Status").font(.headline)
      Text(issue.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
      Divider()
      PickerOptionRow(isDisabled: true, action: {}) {
        Label("Open", systemImage: "checkmark")
      }
      PickerOptionRow(isDisabled: store.updatingIssueTarget == .github(issue.id)) {
        Task { await store.changeGitHubIssueState(issueID: issue.id, isOpen: false) }
      } content: {
        Label("Closed", systemImage: "checkmark.circle")
      }
      .accessibilityIdentifier("github.status.closed")
    }
    .padding(12)
    .frame(width: 240)
  }
}

/// Native popover for changing the status of a hovered Linear issue.
private struct StatusPickerPopover: View {
  @EnvironmentObject private var store: StatusStore

  /// Issue whose status can be changed.
  let issue: LinearIssueItem

  /// Builds the status picker popover.
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Change Status")
        .font(.headline)

      Text(issue.title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Divider()

      VStack(alignment: .leading, spacing: 0) {
        ForEach(issue.workflowStates) { state in
          PickerOptionRow(
            isDisabled: state.id == issue.stateID || store.updatingIssueTarget == .linear(issue.id),
            action: {
              Task {
                await store.changeIssueStatus(issueID: issue.id, state: state)
              }
            }
          ) {
            HStack(spacing: 8) {
              Image(systemName: state.id == issue.stateID ? "checkmark" : statusIcon(for: state))
                .frame(width: 16)
                .foregroundStyle(statusColor(for: state))

              Text(state.name)

              Spacer(minLength: 0)
            }
          }
          .accessibilityLabel(state.name)
          .accessibilityHint("Change issue status")
          .accessibilityIdentifier("linear.status.\(state.id)")
        }
      }
    }
    .padding(12)
    .frame(width: 240)
  }

  /// Returns a semantic symbol for a workflow state.
  private func statusIcon(for state: LinearWorkflowState) -> String {
    switch state.type {
    case "completed":
      "checkmark.circle.fill"
    case "started":
      "play.circle.fill"
    case "canceled":
      "xmark.circle.fill"
    case "backlog":
      "ellipsis.circle"
    default:
      "circle"
    }
  }

  /// Returns a semantic color for a workflow state.
  private func statusColor(for state: LinearWorkflowState) -> Color {
    switch state.type {
    case "completed":
      .blue
    case "started":
      .yellow
    case "canceled":
      .red
    case "backlog":
      .secondary
    default:
      .secondary
    }
  }
}

/// Native popover for changing the priority of a hovered Linear issue.
private struct PriorityPickerPopover: View {
  @EnvironmentObject private var store: StatusStore

  /// Issue whose priority can be changed.
  let issue: LinearIssueItem

  /// Builds the priority picker popover.
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Change Priority")
        .font(.headline)

      Text(issue.title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Divider()

      VStack(alignment: .leading, spacing: 0) {
        ForEach(LinearPriorityOption.allCases) { priority in
          PickerOptionRow(
            isDisabled: priority.value == issue.priority || store.updatingPriorityIssueID == issue.id,
            action: {
              Task {
                await store.changeIssuePriority(issueID: issue.id, priority: priority)
              }
            }
          ) {
            HStack(spacing: 8) {
              Image(systemName: priority.value == issue.priority ? "checkmark" : priorityStyle(for: priority).systemImage)
                .frame(width: 16)
                .foregroundStyle(priorityStyle(for: priority).color)

              Text(priority.label)

              Spacer(minLength: 0)
            }
          }
          .accessibilityLabel(priority.label)
          .accessibilityHint("Change issue priority")
          .accessibilityIdentifier("linear.priority.\(priority.value)")
        }
      }
    }
    .padding(12)
    .frame(width: 240)
  }

  /// Visual style for a Linear priority option.
  private func priorityStyle(for priority: LinearPriorityOption) -> MetadataStyle {
    switch priority.value {
    case 1:
      MetadataStyle(systemImage: "exclamationmark.square.fill", color: .orange)
    case 2:
      MetadataStyle(systemImage: "arrow.up.circle.fill", color: .orange)
    case 3:
      MetadataStyle(systemImage: "equal.circle.fill", color: .yellow)
    case 4:
      MetadataStyle(systemImage: "arrow.down.circle.fill", color: .secondary)
    default:
      MetadataStyle(systemImage: "ellipsis.circle", color: .secondary)
    }
  }
}

/// Native popover for changing the due date of a hovered Linear issue.
private struct DueDatePickerPopover: View {
  @EnvironmentObject private var store: StatusStore

  /// Issue whose due date can be changed.
  let issue: LinearIssueItem

  /// Date currently selected in the calendar.
  @State private var selectedDate: Date

  init(issue: LinearIssueItem) {
    self.issue = issue
    _selectedDate = State(
      initialValue: Self.parseDueDate(issue.dueDate) ?? Calendar.current.startOfDay(for: Date())
    )
  }

  /// Builds the due date picker popover.
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Change Due Date")
        .font(.headline)

      Text(issue.title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Divider()

      GraphicalDatePicker(selection: $selectedDate)
        .disabled(store.updatingDueDateIssueID == issue.id)
        .accessibilityIdentifier("linear.dueDate.calendar.\(issue.id)")

      if issue.dueDate != nil {
        Button(role: .destructive) {
          Task { await store.changeIssueDueDate(issueID: issue.id, dueDate: nil) }
        } label: {
          Label("Remove due date", systemImage: "xmark.circle")
            .font(.caption)
        }
        .buttonStyle(.plain)
        .disabled(store.updatingDueDateIssueID == issue.id)
        .accessibilityIdentifier("linear.dueDate.remove.\(issue.id)")
      }
    }
    .padding(12)
    .onChange(of: selectedDate) { _, newDate in
      guard store.updatingDueDateIssueID != issue.id else { return }
      Task { await store.changeIssueDueDate(issueID: issue.id, dueDate: newDate) }
    }
  }

  /// Parses Linear's `YYYY-MM-DD` due date string.
  private static func parseDueDate(_ rawDate: String?) -> Date? {
    guard let rawDate else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: rawDate)
  }
}

/// Calendar section listing timed events remaining today.
private struct CalendarSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Timed calendar events to display.
  let events: [CalendarEventItem]

  /// Tomorrow's timed calendar events.
  let tomorrowEvents: [CalendarEventItem]

  /// Recoverable account- or calendar-scoped loading warnings.
  let warnings: [String]

  /// Identifier for the event currently under the pointer.
  let hoveredEventID: CalendarEventItem.ID?

  /// Whether tomorrow's events should be displayed.
  let isTomorrowExpanded: Bool

  /// Current clock tick used to identify meetings happening now.
  let now: Date

  /// Builds the calendar section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionTitle(title: "Up Next")

        Spacer(minLength: 0)

        Button {
          store.openGoogleCalendar()
        } label: {
          Image(systemName: "plus")
            .padding(5)
            .contentShape(Rectangle())
            .hoverHighlight(isHovered: store.hoveredControlID == .openGoogleCalendar)
        }
        .buttonStyle(.plain)
        .help("Open Google Calendar")
        .accessibilityLabel("Open Google Calendar")
        .accessibilityHint("Open Google Calendar's week view to create an event")
        .accessibilityIdentifier("calendar.new")
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .openGoogleCalendar : nil)
        }
      }

      ForEach(Array(warnings.prefix(2).enumerated()), id: \.offset) { _, warning in
        MessageRow(title: "Calendar issue", detail: warning)
      }

      VStack(alignment: .leading, spacing: 0) {
          if events.isEmpty {
            MessageRow(title: "No more events today", detail: nil)
              .padding(.horizontal, 16)
              .padding(.vertical, 5)
          } else {
            ForEach(events) { event in
              EventRow(
                event: event,
                isHovered: hoveredEventID == event.id,
                now: now,
                showsSource: store.showsCalendarSourceNames,
                isCopied: store.copiedEventID == event.id
              )
                .onHover { isHovered in
                  store.setHoveredEvent(isHovered ? event.id : nil)
                }
              }
          }

          TomorrowEventsButton(isExpanded: isTomorrowExpanded) {
            store.toggleTomorrowEvents()
          }

          if isTomorrowExpanded {
            VStack(alignment: .leading, spacing: 8) {
              SectionTitle(title: "Tomorrow")

              if tomorrowEvents.isEmpty {
                MessageRow(title: "No timed events tomorrow", detail: nil)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 5)
              } else {
                VStack(alignment: .leading, spacing: 0) {
                  ForEach(tomorrowEvents) { event in
                    EventRow(
                      event: event,
                      isHovered: hoveredEventID == event.id,
                      now: now,
                      showsSource: store.showsCalendarSourceNames,
                      isCopied: store.copiedEventID == event.id
                    )
                      .onHover { isHovered in
                        store.setHoveredEvent(isHovered ? event.id : nil)
                      }
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            .padding(.top, 4)
          }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Full-width row button that expands or collapses tomorrow's events.
private struct TomorrowEventsButton: View {
  @EnvironmentObject private var store: StatusStore

  /// Whether tomorrow's events are currently visible.
  let isExpanded: Bool

  /// Action run when the user toggles tomorrow's events.
  let action: () -> Void

  /// Builds the tomorrow disclosure row.
  var body: some View {
    HStack {
      Button(action: action) {
        HStack(spacing: 6) {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
          Text(isExpanded ? "Hide tomorrow" : "Show tomorrow")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .hoverHighlight(isHovered: store.hoveredControlID == .tomorrowEvents)
      }
      .buttonStyle(.plain)
      .onHover { isHovered in
        store.setHoveredControl(isHovered ? .tomorrowEvents : nil)
      }
      .accessibilityLabel(isExpanded ? "Hide tomorrow" : "Show tomorrow")
      .accessibilityHint("Expand or collapse tomorrow's calendar events")
      .accessibilityIdentifier("calendar.tomorrow.toggle")

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
  }
}

/// Linear section listing assigned issues by priority.
private struct LinearSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Assigned Linear issues to display.
  let issues: [LinearIssueItem]

  /// Optional Linear loading error.
  let error: String?

  /// Identifier for the issue currently under the pointer.
  let hoveredIssueTarget: IssueActionTarget?

  /// Identifier for the issue whose link was just copied.
  let copiedIssueTarget: IssueActionTarget?

  /// Identifier for the issue whose status is being updated.
  let updatingIssueTarget: IssueActionTarget?

  /// Identifier for the issue whose priority is being updated.
  let updatingPriorityIssueID: LinearIssueItem.ID?

  /// Identifier for the issue whose due date is being updated.
  let updatingDueDateIssueID: LinearIssueItem.ID?

  /// Builds the Linear section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let error {
        MessageRow(title: "Linear unavailable", detail: error)
          .transition(.opacity)
      } else if issues.isEmpty {
        if store.isRefreshing {
          LoadingIssuesRow()
            .transition(.opacity)
        } else {
          MessageRow(title: "No active issues", detail: nil)
            .transition(.opacity)
        }
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(issues) { issue in
            IssueRow(
              issue: issue,
              isHovered: hoveredIssueTarget == .linear(issue.id),
              isCopied: copiedIssueTarget == .linear(issue.id),
              isUpdating: updatingIssueTarget == .linear(issue.id)
                || updatingPriorityIssueID == issue.id
                || updatingDueDateIssueID == issue.id,
              copyHotkey: store.copyIssueHotkey,
              statusHotkey: store.statusPickerHotkey,
              priorityHotkey: store.priorityPickerHotkey,
              dueDateHotkey: store.dueDatePickerHotkey,
              labelHotkey: store.labelPickerHotkey,
              assigneeHotkey: store.assigneePickerHotkey,
              cancel: {
                Task { await store.cancelLinearIssue(issueID: issue.id) }
              }
            )
            .onHover { isHovered in
              store.setHoveredIssue(isHovered ? .linear(issue.id) : nil)
            }
            .popover(isPresented: statusPickerBinding(for: issue.id), arrowEdge: .trailing) {
              StatusPickerPopover(issue: issue)
                .environmentObject(store)
            }
            .popover(isPresented: priorityPickerBinding(for: issue.id), arrowEdge: .trailing) {
              PriorityPickerPopover(issue: issue)
                .environmentObject(store)
            }
            .popover(isPresented: dueDatePickerBinding(for: issue.id), arrowEdge: .trailing) {
              DueDatePickerPopover(issue: issue)
                .environmentObject(store)
            }
            .popover(isPresented: labelPickerBinding(for: .linear(issue.id)), arrowEdge: .trailing) {
              IssueMultiValuePickerPopover(target: .linear(issue.id), title: issue.title, kind: .labels)
                .environmentObject(store)
            }
            .popover(isPresented: assigneePickerBinding(for: .linear(issue.id)), arrowEdge: .trailing) {
              IssueMultiValuePickerPopover(target: .linear(issue.id), title: issue.title, kind: .assignees)
                .environmentObject(store)
            }
          }

          if store.hasMoreIssues || store.hasExpandedIssues {
            MoreIssuesControls(
              canShowMore: store.hasMoreIssues,
              canShowLess: store.hasExpandedIssues,
              showMoreTitle: store.showMoreIssuesLabel
            ) {
              store.showMoreIssues()
            } showLess: {
              store.showFewerIssues()
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .animation(.smooth(duration: 0.2), value: issues.isEmpty)
    .animation(.smooth(duration: 0.2), value: store.isRefreshing)
  }

  /// Binding that anchors the status chooser to its selected issue row.
  private func statusPickerBinding(for issueID: LinearIssueItem.ID) -> Binding<Bool> {
    Binding(
      get: { store.statusPickerTarget == .linear(issueID) },
      set: { isPresented in
        if !isPresented, store.statusPickerTarget == .linear(issueID) {
          store.dismissStatusPicker()
        }
      }
    )
  }

  /// Binding that anchors the priority chooser to its selected issue row.
  private func priorityPickerBinding(for issueID: LinearIssueItem.ID) -> Binding<Bool> {
    Binding(
      get: { store.priorityPickerIssueID == issueID },
      set: { isPresented in
        if !isPresented, store.priorityPickerIssueID == issueID {
          store.dismissPriorityPicker()
        }
      }
    )
  }

  /// Binding that anchors the due date chooser to its selected issue row.
  private func dueDatePickerBinding(for issueID: LinearIssueItem.ID) -> Binding<Bool> {
    Binding(
      get: { store.dueDatePickerIssueID == issueID },
      set: { isPresented in
        if !isPresented, store.dueDatePickerIssueID == issueID {
          store.dismissDueDatePicker()
        }
      }
    )
  }

  private func labelPickerBinding(for target: IssueActionTarget) -> Binding<Bool> {
    Binding(get: { store.labelPickerTarget == target }, set: { if !$0 { store.dismissLabelPicker() } })
  }

  private func assigneePickerBinding(for target: IssueActionTarget) -> Binding<Bool> {
    Binding(get: { store.assigneePickerTarget == target }, set: { if !$0 { store.dismissAssigneePicker() } })
  }
}

/// GitHub issues section of the menu popover.
private struct GitHubSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Assigned open GitHub issues to display.
  let issues: [GitHubIssueItem]

  /// Optional GitHub loading error.
  let error: String?

  /// Identifier for the issue currently under the pointer.
  let hoveredIssueTarget: IssueActionTarget?

  /// Identifier for the issue whose link was just copied.
  let copiedIssueTarget: IssueActionTarget?

  /// Builds the GitHub section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let error {
        MessageRow(title: "GitHub unavailable", detail: error)
          .transition(.opacity)
      } else if issues.isEmpty {
        if store.isRefreshing {
          LoadingIssuesRow()
            .transition(.opacity)
        } else {
          MessageRow(title: "No open issues", detail: nil)
            .transition(.opacity)
        }
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(issues) { issue in
            GitHubIssueRow(
              issue: issue,
              isHovered: hoveredIssueTarget == .github(issue.id),
              isCopied: copiedIssueTarget == .github(issue.id)
            )
            .onHover { isHovered in
              store.setHoveredIssue(isHovered ? .github(issue.id) : nil)
            }
            .popover(isPresented: statusPickerBinding(for: issue.id), arrowEdge: .trailing) {
              GitHubStatusPickerPopover(issue: issue).environmentObject(store)
            }
            .popover(isPresented: labelPickerBinding(for: .github(issue.id)), arrowEdge: .trailing) {
              IssueMultiValuePickerPopover(target: .github(issue.id), title: issue.title, kind: .labels)
                .environmentObject(store)
            }
            .popover(isPresented: assigneePickerBinding(for: .github(issue.id)), arrowEdge: .trailing) {
              IssueMultiValuePickerPopover(target: .github(issue.id), title: issue.title, kind: .assignees)
                .environmentObject(store)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .animation(.smooth(duration: 0.2), value: issues.isEmpty)
    .animation(.smooth(duration: 0.2), value: store.isRefreshing)
  }

  private func statusPickerBinding(for issueID: String) -> Binding<Bool> {
    Binding(get: { store.statusPickerTarget == .github(issueID) }, set: { if !$0 { store.dismissStatusPicker() } })
  }

  private func labelPickerBinding(for target: IssueActionTarget) -> Binding<Bool> {
    Binding(get: { store.labelPickerTarget == target }, set: { if !$0 { store.dismissLabelPicker() } })
  }

  private func assigneePickerBinding(for target: IssueActionTarget) -> Binding<Bool> {
    Binding(get: { store.assigneePickerTarget == target }, set: { if !$0 { store.dismissAssigneePicker() } })
  }
}

/// One compact GitHub issue row that opens the issue in the browser.
private struct GitHubIssueRow: View {
  @EnvironmentObject private var store: StatusStore
  /// Issue represented by the row.
  let issue: GitHubIssueItem

  /// Whether the pointer is currently over the row.
  let isHovered: Bool

  /// Whether this row should show a recent copy confirmation.
  let isCopied: Bool

  /// Builds the issue row.
  var body: some View {
    Button {
      if let url = issue.url {
        NSWorkspace.shared.open(url)
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(issue.title.compactLine(limit: 72))
          .font(.callout.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .multilineTextAlignment(.leading)

        HStack(spacing: 6) {
          MetadataPill(
            title: issue.reference,
            systemImage: "smallcircle.filled.circle",
            color: .green
          )

          if let updatedAt = issue.updatedAt {
            MetadataPill(
              title: "Updated \(DisplayFormatters.relative.localizedString(fromTimeInterval: updatedAt.timeIntervalSinceNow))",
              systemImage: "clock",
              color: .secondary
            )
          }

          if isCopied {
            Spacer(minLength: 0)

            Label("Copied", systemImage: "checkmark")
              .font(.caption)
              .foregroundStyle(.green)
              .transition(.opacity)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 3)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .background {
        if isHovered {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
        }
      }
      .animation(.easeOut(duration: 0.12), value: isHovered)
      .animation(.easeOut(duration: 0.12), value: isCopied)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(issue.title), \(issue.reference)")
    .accessibilityHint("Opens the GitHub issue. Press \(store.copyIssueHotkey.uppercased()) to copy, \(store.statusPickerHotkey.uppercased()) for status, \(store.labelPickerHotkey.uppercased()) for labels, or \(store.assigneePickerHotkey.uppercased()) for assignees while hovering.")
    .accessibilityIdentifier("github.issue.\(issue.id)")
    .disabled(issue.url == nil)
    .frame(height: workItemRowHeight)
  }
}


/// Local section listing recent notes.
private struct NotesSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Local notes to display.
  let notes: [LocalNoteItem]

  /// Optional local loading error.
  let error: String?

  /// Identifier for the note currently under the pointer.
  let hoveredNoteID: LocalNoteItem.ID?

  /// Action run when the user creates a new note.
  let openNewNote: () -> Void

  /// Action run when the user opens an existing note.
  let openNote: (LocalNoteItem) -> Void

  /// Builds the local section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionTitle(title: "Notes")

        Spacer(minLength: 0)

        Button(action: openNewNote) {
          Image(systemName: "plus")
            .padding(5)
            .contentShape(Rectangle())
            .hoverHighlight(isHovered: store.hoveredControlID == .newNote)
        }
        .buttonStyle(.plain)
        .help("New note")
        .accessibilityLabel("New note")
        .accessibilityHint("Create a local note")
        .accessibilityIdentifier("notes.new")
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .newNote : nil)
        }
      }

      if let error {
        MessageRow(title: "Notes unavailable", detail: error)
      } else if notes.isEmpty {
        MessageRow(title: "No notes", detail: nil)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(notes) { note in
            NoteRow(
              note: note,
              isHovered: hoveredNoteID == note.id,
              open: {
                openNote(note)
              },
              delete: {
                store.deleteLocalNote(id: note.id)
              }
            )
            .onHover { isHovered in
              store.setHoveredNote(isHovered ? note.id : nil)
            }
          }

          if store.hasMoreNotes || store.hasExpandedNotes {
            MoreNotesControls(
              canShowMore: store.hasMoreNotes,
              canShowLess: store.hasExpandedNotes,
              showMoreTitle: store.showMoreNotesLabel
            ) {
              store.showMoreNotes()
            } showLess: {
              store.showFewerNotes()
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

/// Compact controls that reveal or collapse fetched local notes.
private struct MoreNotesControls: View {
  @EnvironmentObject private var store: StatusStore

  /// Whether another page can be revealed.
  let canShowMore: Bool

  /// Whether expanded notes can be collapsed.
  let canShowLess: Bool

  /// Reveal-more button title.
  let showMoreTitle: String

  /// Action run when the user asks for more notes.
  let showMore: () -> Void

  /// Action run when the user asks for fewer notes.
  let showLess: () -> Void

  /// Builds the note disclosure control row.
  var body: some View {
    HStack {
      if canShowMore {
        Button(action: showMore) {
          HStack(spacing: 6) {
            Image(systemName: "chevron.down")
            Text(showMoreTitle)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
          .hoverHighlight(isHovered: store.hoveredControlID == .moreNotes)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .moreNotes : nil)
        }
        .accessibilityLabel(showMoreTitle)
        .accessibilityHint("Show more local notes")
        .accessibilityIdentifier("notes.showMore")
      }

      Spacer(minLength: 0)

      if canShowLess {
        Button(action: showLess) {
          HStack(spacing: 6) {
            Image(systemName: "chevron.up")
            Text("Show less")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
          .hoverHighlight(isHovered: store.hoveredControlID == .fewerNotes)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .fewerNotes : nil)
        }
        .accessibilityLabel("Show less")
        .accessibilityHint("Collapse extra local notes")
        .accessibilityIdentifier("notes.showLess")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
  }
}

/// Compact controls that reveal or collapse fetched Linear issues.
private struct MoreIssuesControls: View {
  @EnvironmentObject private var store: StatusStore

  /// Whether another page can be revealed.
  let canShowMore: Bool

  /// Whether expanded issues can be collapsed.
  let canShowLess: Bool

  /// Reveal-more button title.
  let showMoreTitle: String

  /// Action run when the user asks for more issues.
  let showMore: () -> Void

  /// Action run when the user asks for fewer issues.
  let showLess: () -> Void

  /// Builds the issue disclosure control row.
  var body: some View {
    HStack {
      if canShowMore {
        Button(action: showMore) {
          HStack(spacing: 6) {
            Image(systemName: "chevron.down")
            Text(showMoreTitle)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
          .hoverHighlight(isHovered: store.hoveredControlID == .moreIssues)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .moreIssues : nil)
        }
        .accessibilityLabel(showMoreTitle)
        .accessibilityHint("Show more Linear issues")
        .accessibilityIdentifier("linear.showMore")
      }

      Spacer(minLength: 0)

      if canShowLess {
        Button(action: showLess) {
          HStack(spacing: 6) {
            Image(systemName: "chevron.up")
            Text("Show less")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
          .hoverHighlight(isHovered: store.hoveredControlID == .fewerIssues)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
          store.setHoveredControl(isHovered ? .fewerIssues : nil)
        }
        .accessibilityLabel("Show less")
        .accessibilityHint("Collapse extra Linear issues")
        .accessibilityIdentifier("linear.showLess")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
  }
}

/// Muted section title.
private struct SectionTitle: View {
  /// Section title text.
  let title: String

  /// Builds the section title.
  var body: some View {
    Text(title)
      .foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
  }
}

/// One timed calendar event row.
private struct EventRow: View {
  /// Event represented by the row.
  let event: CalendarEventItem

  /// Whether the pointer is currently over the row.
  let isHovered: Bool

  /// Current clock tick used to decide whether this event is in progress.
  let now: Date

  /// Whether the source calendar name should be shown.
  let showsSource: Bool

  /// Whether this row should show a recent copy confirmation.
  let isCopied: Bool

  /// Fixed row height based on whether a source calendar label is shown.
  private var rowHeight: CGFloat {
    showsSourceLabel ? eventRowHeight : compactEventRowHeight
  }

  /// Whether this row renders a source calendar label.
  private var showsSourceLabel: Bool {
    showsSource && event.sourceLabel != nil
  }

  /// Builds the event row.
  var body: some View {
    Button {
      if let url = event.openURL {
        NSWorkspace.shared.open(url)
      }
    } label: {
      eventContent
        .frame(height: rowHeight, alignment: .leading)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(event.openURL == nil ? "No openable link is available" : "Open meeting link, location link, or calendar event")
    .accessibilityIdentifier("calendar.event.\(event.id)")
    .disabled(event.openURL == nil)
  }

  /// Main event content.
  private var eventContent: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(DisplayFormatters.eventTimeRange(start: event.startDate, end: event.endDate))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 112, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.callout.weight(.medium))
          .foregroundStyle(.primary)
          .lineLimit(showsSourceLabel ? 2 : 1)
          .multilineTextAlignment(.leading)

        if showsSource, let sourceLabel = event.sourceLabel {
          Text(sourceLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)

      if isCopied {
        Label("Copied", systemImage: "checkmark")
          .font(.caption)
          .foregroundStyle(.green)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      if isCurrent || isHovered {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(rowBackgroundColor)
      }
    }
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .animation(.easeOut(duration: 0.12), value: isCurrent)
    .animation(.easeOut(duration: 0.12), value: isCopied)
    .contentShape(Rectangle())
  }

  /// VoiceOver summary for the calendar event row.
  private var accessibilityLabel: String {
    let time = DisplayFormatters.eventTimeRange(start: event.startDate, end: event.endDate)
    if let source = event.accessibilitySourceLabel {
      return "\(event.title), \(time), \(source)"
    }
    return "\(event.title), \(time)"
  }

  /// Whether this calendar event is currently in progress.
  private var isCurrent: Bool {
    event.isHappening(at: now)
  }

  /// Subtle row background that keeps active meetings visibly green.
  private var rowBackgroundColor: Color {
    if isCurrent {
      return Color.green.opacity(isHovered ? 0.16 : 0.10)
    }

    return Color.primary.opacity(0.06)
  }
}

/// One Linear issue row with title-first layout and muted metadata.
private struct IssueRow: View {
  /// Issue represented by the row.
  let issue: LinearIssueItem

  /// Whether the pointer is currently over the row.
  let isHovered: Bool

  /// Whether this row should show a recent copy confirmation.
  let isCopied: Bool

  /// Whether this row should show an in-flight Linear update.
  let isUpdating: Bool

  /// Keyboard character that copies the issue URL while hovering.
  let copyHotkey: String

  /// Keyboard character that opens the status picker while hovering.
  let statusHotkey: String

  /// Keyboard character that opens the priority picker while hovering.
  let priorityHotkey: String

  /// Keyboard character that opens the due date picker while hovering.
  let dueDateHotkey: String

  let labelHotkey: String

  let assigneeHotkey: String

  /// Action run when the issue is canceled.
  let cancel: () -> Void

  /// Builds the issue row.
  var body: some View {
    GeometryReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          Button {
            if let url = issue.url {
              NSWorkspace.shared.open(url)
            }
          } label: {
            issueContent
              .frame(width: proxy.size.width, height: workItemRowHeight, alignment: .leading)
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(accessibilityLabel)
          .accessibilityHint(accessibilityHint)
          .accessibilityIdentifier("linear.issue.\(issue.id)")
          .disabled(issue.url == nil)

          CompactDestructiveActionButton(
            systemImage: "trash",
            accessibilityLabel: "Cancel Linear issue",
            accessibilityHint: "Moves this Linear issue to its canceled state",
            accessibilityIdentifier: "linear.cancel.\(issue.id)",
            confirmationTitle: "Cancel issue?",
            confirmationMessage: "Move \(issue.id) to its canceled Linear state.",
            action: cancel
          )
        }
      }
      .scrollContentBackground(.hidden)
      .clipped()
    }
    .frame(height: workItemRowHeight)
  }

  /// Main issue content that slides left to expose the cancel action.
  private var issueContent: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(issue.title.compactLine(limit: 72))
        .font(.callout.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .multilineTextAlignment(.leading)

      HStack(spacing: 6) {
        MetadataPill(
          title: issue.stateName,
          systemImage: statusStyle.systemImage,
          color: statusStyle.color
        )

        MetadataPill(
          title: issue.priorityLabel,
          systemImage: priorityStyle.systemImage,
          color: priorityStyle.color
        )

        if let dueDate = issue.dueDate, !dueDate.isEmpty {
          MetadataPill(
            title: DisplayFormatters.linearDueDate(dueDate),
            systemImage: "calendar",
            color: .secondary
          )
        }

        if isCopied {
          Spacer(minLength: 0)

          Label("Copied", systemImage: "checkmark")
            .font(.caption)
            .foregroundStyle(.green)
            .transition(.opacity)
        }

        if isUpdating {
          Spacer(minLength: 0)

          Label("Updating", systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .transition(.opacity)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      if isHovered {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(0.06))
      }
    }
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .animation(.easeOut(duration: 0.12), value: isCopied)
  }

  /// VoiceOver summary for the Linear issue row.
  private var accessibilityLabel: String {
    var parts = [issue.title, issue.stateName, issue.priorityLabel]
    if let dueDate = issue.dueDate, !dueDate.isEmpty {
      parts.append("Due \(DisplayFormatters.linearDueDate(dueDate))")
    }
    return parts.joined(separator: ", ")
  }

  /// VoiceOver hint with the user-configured Linear row shortcuts.
  private var accessibilityHint: String {
    guard issue.url != nil else {
      return "No Linear link is available"
    }

    return "Open Linear issue. Press \(copyHotkey.uppercased()) to copy, \(statusHotkey.uppercased()) for status, \(priorityHotkey.uppercased()) for priority, \(dueDateHotkey.uppercased()) for due date, \(labelHotkey.uppercased()) for labels, or \(assigneeHotkey.uppercased()) for assignee while hovering."
  }

  /// Visual style for the Linear workflow state.
  private var statusStyle: MetadataStyle {
    let state = issue.stateName.lowercased()

    if state.contains("progress") {
      return MetadataStyle(systemImage: "play.circle.fill", color: .yellow)
    }
    if state.contains("review") {
      return MetadataStyle(systemImage: "checkmark.circle.fill", color: .green)
    }
    if state.contains("done") || state.contains("complete") {
      return MetadataStyle(systemImage: "checkmark.circle.fill", color: .blue)
    }
    if state.contains("cancel") {
      return MetadataStyle(systemImage: "xmark.circle.fill", color: .red)
    }
    if state.contains("backlog") {
      return MetadataStyle(systemImage: "ellipsis.circle", color: .secondary)
    }
    return MetadataStyle(systemImage: "circle", color: .secondary)
  }

  /// Visual style for the Linear priority label.
  private var priorityStyle: MetadataStyle {
    switch issue.priority {
    case 1:
      return MetadataStyle(systemImage: "exclamationmark.square.fill", color: .orange)
    case 2:
      return MetadataStyle(systemImage: "arrow.up.circle.fill", color: .orange)
    case 3:
      return MetadataStyle(systemImage: "equal.circle.fill", color: .yellow)
    case 4:
      return MetadataStyle(systemImage: "arrow.down.circle.fill", color: .secondary)
    default:
      return MetadataStyle(systemImage: "ellipsis.circle", color: .secondary)
    }
  }
}

/// Compact circular destructive action revealed by horizontal row scrolling.
private struct CompactDestructiveActionButton: View {
  /// SF Symbol shown inside the destructive action.
  let systemImage: String

  /// VoiceOver label for the button.
  let accessibilityLabel: String

  /// VoiceOver hint for the button.
  let accessibilityHint: String

  /// Stable UI test identifier.
  let accessibilityIdentifier: String

  /// Confirmation title shown before running the destructive action.
  let confirmationTitle: String?

  /// Optional confirmation detail shown before running the destructive action.
  let confirmationMessage: String?

  /// Action run when the button is pressed.
  let action: () -> Void

  /// Builds the destructive action button.
  var body: some View {
    Button(role: .destructive, action: runAction) {
      ZStack {
        Circle()
          .fill(Color.red)

        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: destructiveButtonSize, height: destructiveButtonSize)
      .frame(width: destructiveRevealWidth, height: workItemRowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(accessibilityHint)
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  /// Runs the destructive action after optional AppKit confirmation.
  private func runAction() {
    guard let confirmationTitle else {
      action()
      return
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = confirmationTitle
    alert.informativeText = confirmationMessage ?? ""
    alert.addButton(withTitle: accessibilityLabel)
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      action()
    }
  }
}

/// One local note row with a horizontal reveal delete action.
private struct NoteRow: View {
  /// Note represented by the row.
  let note: LocalNoteItem

  /// Whether the pointer is currently over the row.
  let isHovered: Bool

  /// Action run when the note is opened.
  let open: () -> Void

  /// Action run when the note is deleted.
  let delete: () -> Void

  /// Builds the note row.
  var body: some View {
    GeometryReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          Button(action: open) {
            noteContent
              .frame(width: proxy.size.width, height: workItemRowHeight, alignment: .leading)
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(accessibilityLabel)
          .accessibilityHint("Open note editor")
          .accessibilityIdentifier("notes.note.\(note.id)")

          CompactDestructiveActionButton(
            systemImage: "trash",
            accessibilityLabel: "Delete note",
            accessibilityHint: "Deletes this local note",
            accessibilityIdentifier: "notes.delete.\(note.id)",
            confirmationTitle: "Delete note?",
            confirmationMessage: "Delete \(note.title.compactLine(limit: 64)) from local notes.",
            action: delete
          )
        }
      }
      .scrollContentBackground(.hidden)
      .clipped()
    }
    .frame(height: workItemRowHeight)
  }

  /// Main note content that slides left to expose the delete action.
  private var noteContent: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(note.title.compactLine(limit: 64))
        .font(.callout.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      Text(DisplayFormatters.noteDate(note.updatedAt))
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      if isHovered {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(0.06))
      }
    }
    .animation(.easeOut(duration: 0.12), value: isHovered)
  }

  /// VoiceOver summary for the note row.
  private var accessibilityLabel: String {
    "\(note.title), updated \(DisplayFormatters.noteDate(note.updatedAt))"
  }
}

/// Reusable rounded hover treatment for compact menu buttons.
private struct HoverHighlightModifier: ViewModifier {
  /// Whether the pointer is currently over the modified view.
  let isHovered: Bool

  /// Whether the hover background should be active.
  let isEnabled: Bool

  /// Adds a subtle system-adaptive hover background.
  func body(content: Content) -> some View {
    content
      .background {
        if isHovered && isEnabled {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
        }
      }
      .animation(.easeOut(duration: 0.12), value: isHovered)
  }
}

private extension View {
  /// Applies the menu's standard rounded hover background.
  func hoverHighlight(isHovered: Bool, isEnabled: Bool = true) -> some View {
    modifier(HoverHighlightModifier(isHovered: isHovered, isEnabled: isEnabled))
  }
}

/// Icon and color pairing for compact metadata.
private struct MetadataStyle {
  /// SF Symbol displayed before the metadata text.
  let systemImage: String

  /// Semantic color for the metadata icon.
  let color: Color
}

/// Small Linear-style metadata pill.
private struct MetadataPill: View {
  /// Text shown in the pill.
  let title: String

  /// SF Symbol shown before the text.
  let systemImage: String

  /// Semantic icon color.
  let color: Color

  /// Builds the metadata pill.
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: systemImage)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

/// Compact empty and error state row.
private struct MessageRow: View {
  /// Primary message.
  let title: String

  /// Optional secondary detail.
  let detail: String?

  /// Builds the message row.
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.callout)
        .foregroundStyle(.secondary)

      if let detail, !detail.isEmpty {
        Text(detail.compactLine(limit: 96))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(2)
      }
    }
  }
}
