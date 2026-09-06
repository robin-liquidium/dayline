import SwiftUI

/// Top-level grouping for the settings window tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
  case general
  case accounts
  case calendar
  case issues
  case notes
  case shortcuts

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .accounts: "Accounts"
    case .calendar: "Calendar"
    case .issues: "Issues"
    case .notes: "Notes"
    case .shortcuts: "Shortcuts"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .accounts: "person.crop.circle"
    case .calendar: "calendar"
    case .issues: "checklist"
    case .notes: "note.text"
    case .shortcuts: "keyboard"
    }
  }
}

/// One searchable settings entry that deep-links into a tab.
struct SettingsSearchItem: Identifiable {
  let id: String
  let title: String
  let section: String
  let tab: SettingsTab
  let keywords: [String]

  func matches(_ query: String) -> Bool {
    let terms = query.split(whereSeparator: \.isWhitespace)
    let fields = [title, section, tab.title] + keywords
    return terms.allSatisfy { term in
      fields.contains { $0.localizedStandardContains(String(term)) }
    }
  }
}

/// Static catalog of every setting, used by the settings search field.
enum SettingsSearchCatalog {
  static let items: [SettingsSearchItem] = [
    SettingsSearchItem(id: "launchAtLogin", title: "Launch at login", section: "General", tab: .general, keywords: ["startup", "open at login", "start automatically", "boot"]),
    SettingsSearchItem(id: "refreshCadence", title: "Refresh interval", section: "General", tab: .general, keywords: ["refresh", "cadence", "reload", "fetch"]),
    SettingsSearchItem(id: "automaticUpdates", title: "Install updates automatically", section: "Updates", tab: .general, keywords: ["auto update", "automatic updates", "sparkle"]),
    SettingsSearchItem(id: "checkForUpdates", title: "Check for updates", section: "Updates", tab: .general, keywords: ["update", "new version"]),
    SettingsSearchItem(id: "submitFeedback", title: "Submit feedback", section: "Feedback and diagnostics", tab: .general, keywords: ["bug", "report", "feature request"]),
    SettingsSearchItem(id: "exportDiagnostics", title: "Export diagnostics", section: "Feedback and diagnostics", tab: .general, keywords: ["logs", "crash reports", "support", "zip"]),
    SettingsSearchItem(id: "version", title: "Version", section: "About", tab: .general, keywords: ["build", "about"]),
    SettingsSearchItem(id: "viewChangelog", title: "View changelog", section: "About", tab: .general, keywords: ["release notes", "what's new"]),

    SettingsSearchItem(id: "googleAccounts", title: "Google accounts", section: "Google", tab: .accounts, keywords: ["calendar accounts", "connect google", "sign in", "calendars"]),
    SettingsSearchItem(id: "linearAccount", title: "Linear workspace", section: "Linear", tab: .accounts, keywords: ["connect linear", "teams", "workspace"]),
    SettingsSearchItem(id: "githubAccount", title: "GitHub account", section: "GitHub", tab: .accounts, keywords: ["repositories", "connect github", "repos"]),
    SettingsSearchItem(id: "appleCalendar", title: "Apple Calendar", section: "Apple Calendar", tab: .accounts, keywords: ["connect calendar", "device calendars", "icloud"]),
    SettingsSearchItem(id: "appleReminders", title: "Apple Reminders", section: "Apple Reminders", tab: .accounts, keywords: ["connect reminders", "lists", "tasks"]),

    SettingsSearchItem(id: "menuBarEventLeadTime", title: "Before event starts", section: "Menu bar title", tab: .calendar, keywords: ["lead time", "upcoming meeting", "menu bar title", "event title"]),
    SettingsSearchItem(id: "showsCalendarSection", title: "Show calendar in menu", section: "Menu", tab: .calendar, keywords: ["calendar section", "events in menu"]),
    SettingsSearchItem(id: "showsAllDayEvents", title: "Show all-day events", section: "Menu", tab: .calendar, keywords: ["calendar all day", "birthdays", "holidays"]),
    SettingsSearchItem(id: "showsLinearSection", title: "Show issues in menu", section: "Menu", tab: .issues, keywords: ["issues section", "linear section", "tickets in menu"]),
    SettingsSearchItem(id: "showsNotesSection", title: "Show notes in menu", section: "Menu", tab: .notes, keywords: ["notes section"]),

    SettingsSearchItem(id: "showsCalendarSourceNames", title: "Show calendar names", section: "Menu", tab: .calendar, keywords: ["source names", "account names"]),
    SettingsSearchItem(id: "meetingAlertEnabled", title: "Full-screen meeting alerts", section: "Meeting alerts", tab: .calendar, keywords: ["alert", "reminder", "notification"]),
    SettingsSearchItem(id: "meetingAlertRequiresMeetingLink", title: "Only alert for meetings with links", section: "Meeting alerts", tab: .calendar, keywords: ["meeting link", "join", "video call", "conference"]),
    SettingsSearchItem(id: "meetingAlertLead", title: "Show alert", section: "Meeting alerts", tab: .calendar, keywords: ["alert lead", "minutes before", "reminder"]),
    SettingsSearchItem(id: "meetingAlertSnooze", title: "Default snooze", section: "Meeting alerts", tab: .calendar, keywords: ["snooze", "delay", "remind me later"]),

    SettingsSearchItem(id: "linearCreateDefaultTeam", title: "Default team", section: "New Linear issues", tab: .issues, keywords: ["linear defaults", "new issue"]),
    SettingsSearchItem(id: "linearCreateDefaultStatus", title: "Default status", section: "New Linear issues", tab: .issues, keywords: ["linear defaults", "new issue", "workflow state"]),
    SettingsSearchItem(id: "linearCreateDefaultPriority", title: "Default priority", section: "New Linear issues", tab: .issues, keywords: ["linear defaults", "new issue", "urgent"]),
    SettingsSearchItem(id: "linearCreateDefaultProject", title: "Default project", section: "New Linear issues", tab: .issues, keywords: ["linear defaults", "new issue"]),
    SettingsSearchItem(id: "linearCreateDefaultLabel", title: "Default label", section: "New Linear issues", tab: .issues, keywords: ["linear defaults", "new issue", "tag"]),
    SettingsSearchItem(id: "githubCreateDefaultRepo", title: "Default repository", section: "New GitHub issues", tab: .issues, keywords: ["github defaults", "new issue", "repo"]),
    SettingsSearchItem(id: "appleReminderDefaultList", title: "Default list", section: "New reminders", tab: .issues, keywords: ["reminders defaults", "new reminder", "list"]),
    SettingsSearchItem(id: "appleReminderDefaultPriority", title: "Default priority", section: "New reminders", tab: .issues, keywords: ["reminders defaults", "new reminder", "priority"]),
    SettingsSearchItem(id: "linearIssueOrder", title: "Linear issue order", section: "Menu", tab: .issues, keywords: ["sort issues", "issue sorting", "linear order"]),
    SettingsSearchItem(id: "linearIssueFilter", title: "Linear issues", section: "Shown issues", tab: .issues, keywords: ["assigned to me", "all open issues", "filter", "issue filter"]),
    SettingsSearchItem(id: "githubIssueFilter", title: "GitHub issues", section: "Shown issues", tab: .issues, keywords: ["assigned to me", "all open issues", "filter", "issue filter"]),

    SettingsSearchItem(id: "issueClickAction", title: "Click an issue", section: "Opening issues", tab: .issues, keywords: ["linear", "github", "browser", "details", "preview", "default action"]),
    SettingsSearchItem(id: "issueClickModifier", title: "Alternate click modifier", section: "Opening issues", tab: .issues, keywords: ["linear", "github", "command", "cmd", "option", "shift", "shortcut", "browser"]),

    SettingsSearchItem(id: "issueRowFieldAssignee", title: "Assignee", section: "Issue details", tab: .issues, keywords: ["row fields", "metadata", "show", "hide", "assigned person"]),
    SettingsSearchItem(id: "issueRowFieldLabels", title: "Labels", section: "Issue details", tab: .issues, keywords: ["row fields", "metadata", "show", "hide", "tags"]),
    SettingsSearchItem(id: "issueRowFieldProject", title: "Project (Linear)", section: "Issue details", tab: .issues, keywords: ["row fields", "metadata", "show", "hide", "linear project"]),
    SettingsSearchItem(id: "issueRowFieldUpdated", title: "Last updated", section: "Issue details", tab: .issues, keywords: ["row fields", "metadata", "show", "hide", "updated timestamp"]),
    SettingsSearchItem(id: "issueRowFieldDueDate", title: "Due date", section: "Issue details", tab: .issues, keywords: ["row fields", "metadata", "show", "hide", "deadline"]),

    SettingsSearchItem(id: "defaultNoteCount", title: "Notes shown", section: "Menu", tab: .notes, keywords: ["note count", "number of notes"]),
    SettingsSearchItem(id: "localNoteSortOrder", title: "Sort notes by", section: "Menu", tab: .notes, keywords: ["note order", "sort notes"]),

    SettingsSearchItem(id: "notesKeepOnTop", title: "Keep note windows on top", section: "Window", tab: .notes, keywords: ["float", "floating", "always on top"]),

    SettingsSearchItem(id: "copyIssueHotkey", title: "Copy issue/meeting link", section: "Hover shortcuts", tab: .shortcuts, keywords: ["hotkey", "copy link", "hover"]),
    SettingsSearchItem(id: "linearCopyStyle", title: "Issue copy target", section: "Hover shortcuts", tab: .shortcuts, keywords: ["copy style", "url", "identifier", "title"]),
    SettingsSearchItem(id: "statusPickerHotkey", title: "Change status", section: "Hover shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "status"]),
    SettingsSearchItem(id: "priorityPickerHotkey", title: "Change priority", section: "Hover shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "priority"]),
    SettingsSearchItem(id: "dueDatePickerHotkey", title: "Change due date", section: "Hover shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "deadline", "due date"]),
    SettingsSearchItem(id: "labelPickerHotkey", title: "Change labels", section: "Hover shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "tags", "labels"]),
    SettingsSearchItem(id: "assigneePickerHotkey", title: "Change assignees", section: "Hover shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "assign"]),
    SettingsSearchItem(id: "newNoteShortcut", title: "New note", section: "Global shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "note"]),
    SettingsSearchItem(id: "newLinearIssueShortcut", title: "New Linear issue", section: "Global shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "issue"]),
    SettingsSearchItem(id: "newGitHubIssueShortcut", title: "New GitHub issue", section: "Global shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "issue", "github"]),
    SettingsSearchItem(id: "newAppleReminderShortcut", title: "New Apple Reminder", section: "Global shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "reminder", "task"]),
    SettingsSearchItem(id: "openGoogleCalendarShortcut", title: "Open Google Calendar", section: "Global shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "calendar"]),
  ]
}
