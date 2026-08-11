import AppKit
import SwiftUI

/// Detail preview for a hovered calendar event.
struct EventPreviewPopover: View {
  let event: CalendarEventItem

  var body: some View {
    PreviewCard(title: event.title, subtitle: event.accessibilitySourceLabel) {
      PreviewRow(label: "When", value: timeRange, systemImage: "clock")

      if let location = event.location, !location.isEmpty {
        PreviewRow(label: "Where", value: location, systemImage: "mappin")
      }

      if let openURL = event.openURL {
        PreviewOpenButton(title: "Open event", url: openURL)
      } else if let calendarURL = event.calendarURL {
        PreviewOpenButton(title: "Open in calendar", url: calendarURL)
      }
    }
  }

  /// Compact start–end time range for the preview.
  private var timeRange: String {
    if event.isAllDay {
      let calendar = Calendar.current
      let inclusiveEnd = Self.inclusiveAllDayEnd(for: event, calendar: calendar)
      let startDay = event.startDate.formatted(date: .abbreviated, time: .omitted)
      let endDay = inclusiveEnd.formatted(date: .abbreviated, time: .omitted)
      return calendar.isDate(event.startDate, inSameDayAs: inclusiveEnd)
        ? "\(startDay), all day"
        : "\(startDay) – \(endDay), all day"
    }
    let start = event.startDate.formatted(date: .omitted, time: .shortened)
    let end = event.endDate.formatted(date: .omitted, time: .shortened)
    let day = event.startDate.formatted(date: .abbreviated, time: .omitted)
    return "\(day), \(start) – \(end)"
  }

  /// Converts an exclusive all-day end into a display end without preceding the start.
  static func inclusiveAllDayEnd(for event: CalendarEventItem, calendar: Calendar) -> Date {
    let candidate = calendar.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
    return max(event.startDate, candidate)
  }
}

/// Detail preview for a hovered Linear issue.
struct LinearIssuePreviewPopover: View {
  let issue: LinearIssueItem

  var body: some View {
    PreviewCard(title: issue.title, subtitle: issue.id) {
      PreviewRow(label: "Status", value: issue.stateName, systemImage: "circle.fill")
      PreviewRow(label: "Priority", value: issue.priorityLabel, systemImage: "flag")

      if let assignee = issue.assignee {
        PreviewRow(label: "Assignee", value: assignee.label, systemImage: "person")
      }

      if !issue.labels.isEmpty {
        PreviewRow(label: "Labels", value: issue.labels.map(\.label).joined(separator: ", "), systemImage: "tag")
      }

      if let projectName = issue.projectName, !projectName.isEmpty {
        PreviewRow(label: "Project", value: projectName, systemImage: "folder")
      }

      if let dueDate = issue.dueDate, !dueDate.isEmpty {
        PreviewRow(label: "Due", value: DisplayFormatters.linearDueDate(dueDate), systemImage: "calendar")
      }

      if let updatedAt = issue.updatedAt {
        PreviewRow(label: "Updated", value: DisplayFormatters.relative.localizedString(fromTimeInterval: updatedAt.timeIntervalSinceNow), systemImage: "clock")
      }

      if let branchName = issue.branchName, !branchName.isEmpty {
        PreviewRow(label: "Branch", value: branchName, systemImage: "arrow.triangle.branch")
      }

      if let url = issue.url {
        PreviewOpenButton(title: "Open in Linear", url: url)
      }
    }
  }
}

/// Detail preview for a hovered GitHub issue.
struct GitHubIssuePreviewPopover: View {
  let issue: GitHubIssueItem

  var body: some View {
    PreviewCard(title: issue.title, subtitle: issue.reference) {
      if !issue.assignees.isEmpty {
        PreviewRow(label: "Assignees", value: issue.assignees.map(\.login).joined(separator: ", "), systemImage: "person")
      }

      if !issue.labels.isEmpty {
        PreviewRow(label: "Labels", value: issue.labels.map(\.name).joined(separator: ", "), systemImage: "tag")
      }

      if let updatedAt = issue.updatedAt {
        PreviewRow(label: "Updated", value: DisplayFormatters.relative.localizedString(fromTimeInterval: updatedAt.timeIntervalSinceNow), systemImage: "clock")
      }

      if let url = issue.url {
        PreviewOpenButton(title: "Open in GitHub", url: url)
      }
    }
  }
}

/// Detail preview for an Apple Reminder.
struct AppleReminderPreviewPopover: View {
  let reminder: AppleReminderItem

  var body: some View {
    PreviewCard(title: reminder.title, subtitle: reminder.listTitle) {
      PreviewRow(label: "Status", value: "Incomplete", systemImage: "circle")
      PreviewRow(label: "Priority", value: reminder.priority.label, systemImage: "flag")

      if let dueDate = reminder.dueDate {
        PreviewRow(
          label: "Due",
          value: DisplayFormatters.appleReminderDueDate(dueDate),
          systemImage: "calendar"
        )
      }

      if reminder.isRecurring {
        PreviewRow(label: "Repeats", value: "Recurring reminder", systemImage: "repeat")
      }

      if let updatedAt = reminder.updatedAt {
        PreviewRow(
          label: "Updated",
          value: DisplayFormatters.relative.localizedString(
            fromTimeInterval: updatedAt.timeIntervalSinceNow
          ),
          systemImage: "clock"
        )
      }

      if let notes = reminder.notes, !notes.isEmpty {
        PreviewRow(label: "Notes", value: notes, systemImage: "text.alignleft", maxLines: 8)
      }

      if let url = Self.safeAttachedURL(reminder.url) {
        PreviewOpenButton(title: "Open attached URL", url: url)
      }
    }
    .accessibilityIdentifier("reminders.preview.\(reminder.id)")
  }

  static func safeAttachedURL(_ url: URL?) -> URL? {
    guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      return nil
    }
    return url
  }
}

/// Shared preview layout: title block plus labeled detail rows and actions.
private struct PreviewCard<Content: View>: View {
  let title: String
  let subtitle: String?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      content
    }
    .padding(12)
    .frame(width: 300, alignment: .leading)
  }
}

/// One labeled detail line inside a preview card.
private struct PreviewRow: View {
  let label: String
  let value: String
  let systemImage: String
  var maxLines: Int? = nil

  var body: some View {
    LabeledContent {
      Text(value)
        .font(.callout)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .lineLimit(maxLines)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
    } label: {
      Label(label, systemImage: systemImage)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }
}

/// Button that opens a preview item in its source app.
private struct PreviewOpenButton: View {
  let title: String
  let url: URL

  var body: some View {
    Button(title) {
      NSWorkspace.shared.open(url)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.small)
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}
