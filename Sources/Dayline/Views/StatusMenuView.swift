import AppKit
import SwiftUI

/// Popover content shown when the user opens the menu bar extra.
struct StatusMenuView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.openSettings) private var openSettings
  @FocusState private var isKeyboardTargetFocused: Bool

  /// Builds the compact menu bar popover content.
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerBar
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if store.hasDependencySetupItems {
            DependencySetupSection(statuses: store.dependencySetupItems)
          }

          CalendarSection(
            events: store.events,
            tomorrowEvents: store.tomorrowEvents,
            error: store.calendarError,
            hoveredEventID: store.hoveredEventID,
            isTomorrowExpanded: store.isTomorrowExpanded
          )
          LinearSection(
            issues: store.issues,
            error: store.linearError,
            hoveredIssueID: store.hoveredIssueID,
            copiedIssueID: store.copiedIssueID,
            updatingStatusIssueID: store.updatingStatusIssueID,
            updatingPriorityIssueID: store.updatingPriorityIssueID
          )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollContentBackground(.hidden)
      .frame(height: scrollContentHeight)
      .clipped()
      footerBar
    }
    .frame(width: 430)
    .focusable()
    .focusEffectDisabled()
    .focused($isKeyboardTargetFocused)
    .onAppear {
      isKeyboardTargetFocused = true
    }
    .onKeyPress { keyPress in
      handleKeyPress(keyPress.characters) ? .handled : .ignored
    }
    .popover(isPresented: statusPickerBinding, arrowEdge: .trailing) {
      if let issue = store.statusPickerIssue {
        StatusPickerPopover(issue: issue)
          .environmentObject(store)
      }
    }
    .popover(isPresented: priorityPickerBinding, arrowEdge: .trailing) {
      if let issue = store.priorityPickerIssue {
        PriorityPickerPopover(issue: issue)
          .environmentObject(store)
      }
    }
  }

  /// Header row with title, freshness, and refresh action.
  private var header: some View {
    HStack(spacing: 10) {
      Label("Today", systemImage: "calendar")

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

  /// Footer row with settings and quit actions.
  private var footer: some View {
    HStack {
      Button {
        openSettings()
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
    let setupRows = store.hasDependencySetupItems ? CGFloat(max(store.dependencySetupItems.count, 1)) * 64 + 44 : 0
    let eventRows = CGFloat(max(store.events.count, 1)) * 34
    let tomorrowRows = store.isTomorrowExpanded ? CGFloat(max(store.tomorrowEvents.count, 1)) * 34 + 34 : 0
    let issueRows = CGFloat(max(store.issues.count, 1)) * 58
    let moreRow: CGFloat = store.hasMoreIssues || store.hasExpandedIssues ? 34 : 0
    return 108 + setupRows + eventRows + tomorrowRows + issueRows + moreRow
  }

  /// Binding used by SwiftUI's native status chooser popover.
  private var statusPickerBinding: Binding<Bool> {
    Binding(
      get: { store.statusPickerIssue != nil },
      set: { isPresented in
        if !isPresented {
          store.dismissStatusPicker()
        }
      }
    )
  }

  /// Binding used by SwiftUI's native priority chooser popover.
  private var priorityPickerBinding: Binding<Bool> {
    Binding(
      get: { store.priorityPickerIssue != nil },
      set: { isPresented in
        if !isPresented {
          store.dismissPriorityPicker()
        }
      }
    )
  }

  /// Handles menu-level keyboard shortcuts.
  private func handleKeyPress(_ characters: String) -> Bool {
    if store.matchesStatusPickerHotkey(characters) {
      return store.presentStatusPickerForHoveredIssue()
    }

    if store.matchesPriorityPickerHotkey(characters) {
      return store.presentPriorityPickerForHoveredIssue()
    }

    if store.matchesCopyIssueHotkey(characters) {
      return store.copyHoveredIssueLink()
    }

    return false
  }
}

/// Setup section shown when required local CLIs are missing or unauthenticated.
private struct DependencySetupSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Dependency statuses that need user attention.
  let statuses: [DependencyStatus]

  /// Builds the setup section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionTitle(title: "Setup")

        Spacer(minLength: 0)

        Button {
          Task { await store.refreshDependencyStatus() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Check again")
        .accessibilityLabel("Check CLI setup again")
        .accessibilityIdentifier("setup.checkAgain")
      }

      VStack(alignment: .leading, spacing: 8) {
        ForEach(statuses) { status in
          DependencySetupRow(status: status)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// One setup row for an external CLI dependency.
private struct DependencySetupRow: View {
  @EnvironmentObject private var store: StatusStore

  /// Dependency status represented by the row.
  let status: DependencyStatus

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
    .padding(.horizontal, 16)
    .padding(.vertical, 7)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.05))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("setup.\(status.kind.id)")
  }

  /// Action button appropriate for the dependency state.
  @ViewBuilder
  private var actionButton: some View {
    switch status.state {
    case .checking:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Checking")
    case .missing:
      Button("Install") {
        store.installDependency(status)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityIdentifier("setup.\(status.kind.id).install")
    case .unauthenticated:
      Button("Auth") {
        store.authenticateDependency(status)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityIdentifier("setup.\(status.kind.id).auth")
    case .ready:
      EmptyView()
    }
  }

  /// Symbol for the current dependency state.
  private var systemImage: String {
    switch status.state {
    case .checking:
      "clock.arrow.circlepath"
    case .missing:
      "arrow.down.circle.fill"
    case .unauthenticated:
      "person.crop.circle.badge.exclamationmark"
    case .ready:
      "checkmark.circle.fill"
    }
  }

  /// Color for the current dependency state symbol.
  private var iconColor: Color {
    switch status.state {
    case .checking:
      .secondary
    case .missing:
      .orange
    case .unauthenticated:
      .yellow
    case .ready:
      .green
    }
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
          Button {
            Task {
              await store.changeIssueStatus(issueID: issue.id, state: state)
            }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: state.id == issue.stateID ? "checkmark" : statusIcon(for: state))
                .frame(width: 16)
                .foregroundStyle(statusColor(for: state))

              Text(state.name)

              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(state.id == issue.stateID || store.updatingStatusIssueID == issue.id)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
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
          Button {
            Task {
              await store.changeIssuePriority(issueID: issue.id, priority: priority)
            }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: priority.value == issue.priority ? "checkmark" : priorityStyle(for: priority).systemImage)
                .frame(width: 16)
                .foregroundStyle(priorityStyle(for: priority).color)

              Text(priority.label)

              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(priority.value == issue.priority || store.updatingPriorityIssueID == issue.id)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
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

/// Calendar section listing timed events remaining today.
private struct CalendarSection: View {
  @EnvironmentObject private var store: StatusStore

  /// Timed calendar events to display.
  let events: [CalendarEventItem]

  /// Tomorrow's timed calendar events.
  let tomorrowEvents: [CalendarEventItem]

  /// Optional calendar loading error.
  let error: String?

  /// Identifier for the event currently under the pointer.
  let hoveredEventID: CalendarEventItem.ID?

  /// Whether tomorrow's events should be displayed.
  let isTomorrowExpanded: Bool

  /// Builds the calendar section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: "Up Next")

      if let error {
        MessageRow(title: "Calendar unavailable", detail: error)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          if events.isEmpty {
            MessageRow(title: "No more events today", detail: nil)
              .padding(.horizontal, 16)
              .padding(.vertical, 5)
          } else {
            ForEach(events) { event in
              EventRow(event: event, isHovered: hoveredEventID == event.id)
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
                    EventRow(event: event, isHovered: hoveredEventID == event.id)
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
  let hoveredIssueID: LinearIssueItem.ID?

  /// Identifier for the issue whose link was just copied.
  let copiedIssueID: LinearIssueItem.ID?

  /// Identifier for the issue whose status is being updated.
  let updatingStatusIssueID: LinearIssueItem.ID?

  /// Identifier for the issue whose priority is being updated.
  let updatingPriorityIssueID: LinearIssueItem.ID?

  /// Builds the Linear section.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: "Linear")

      if let error {
        MessageRow(title: "Linear unavailable", detail: error)
      } else if issues.isEmpty {
        MessageRow(title: "No active issues", detail: nil)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(issues) { issue in
            IssueRow(
              issue: issue,
              isHovered: hoveredIssueID == issue.id,
              isCopied: copiedIssueID == issue.id,
              isUpdating: updatingStatusIssueID == issue.id || updatingPriorityIssueID == issue.id,
              copyHotkey: store.copyIssueHotkey,
              statusHotkey: store.statusPickerHotkey,
              priorityHotkey: store.priorityPickerHotkey
            )
            .onHover { isHovered in
              store.setHoveredIssue(isHovered ? issue.id : nil)
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

  /// Builds the event row.
  var body: some View {
    Button {
      if let url = event.openURL {
        NSWorkspace.shared.open(url)
      }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(DisplayFormatters.eventTimeRange(start: event.startDate, end: event.endDate))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 92, alignment: .leading)

        Text(event.title)
          .font(.callout.weight(.medium))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if isHovered {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
        }
      }
      .animation(.easeOut(duration: 0.12), value: isHovered)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(event.openURL == nil ? "No openable link is available" : "Open meeting link, location link, or calendar event")
    .accessibilityIdentifier("calendar.event.\(event.id)")
    .disabled(event.openURL == nil)
  }

  /// VoiceOver summary for the calendar event row.
  private var accessibilityLabel: String {
    "\(event.title), \(DisplayFormatters.eventTimeRange(start: event.startDate, end: event.endDate))"
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

  /// Builds the issue row.
  var body: some View {
    Button {
      if let url = issue.url {
        NSWorkspace.shared.open(url)
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(issue.title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
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
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
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
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(accessibilityHint)
    .accessibilityIdentifier("linear.issue.\(issue.id)")
    .disabled(issue.url == nil)
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

    return "Open Linear issue. Press \(copyHotkey.uppercased()) to copy, \(statusHotkey.uppercased()) to change status, or \(priorityHotkey.uppercased()) to change priority while hovering."
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
