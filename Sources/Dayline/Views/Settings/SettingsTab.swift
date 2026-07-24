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
    let needle = query.lowercased()
    return title.lowercased().contains(needle)
      || section.lowercased().contains(needle)
      || keywords.contains { $0.lowercased().contains(needle) }
  }
}

/// Static catalog of every setting, used by the settings search field.
enum SettingsSearchCatalog {
  static let items: [SettingsSearchItem] = [
    SettingsSearchItem(id: "launchAtLogin", title: "Launch at login", section: "General", tab: .general, keywords: ["startup", "open at login", "start automatically", "boot"]),
    SettingsSearchItem(id: "refreshCadence", title: "Refresh interval", section: "General", tab: .general, keywords: ["refresh", "cadence", "reload", "fetch"]),
    SettingsSearchItem(id: "automaticUpdates", title: "Install updates automatically", section: "Updates", tab: .general, keywords: ["auto update", "automatic updates", "sparkle"]),
    SettingsSearchItem(id: "checkForUpdates", title: "Check for Updates", section: "Updates", tab: .general, keywords: ["update", "new version"]),
    SettingsSearchItem(id: "submitFeedback", title: "Submit Feedback", section: "Feedback", tab: .general, keywords: ["bug", "report", "feature request"]),
    SettingsSearchItem(id: "version", title: "Version", section: "About", tab: .general, keywords: ["build", "about"]),
    SettingsSearchItem(id: "viewChangelog", title: "View Changelog", section: "About", tab: .general, keywords: ["release notes", "what's new"]),

    SettingsSearchItem(id: "googleAccounts", title: "Google Accounts", section: "Google", tab: .accounts, keywords: ["calendar accounts", "connect google", "sign in", "calendars"]),
    SettingsSearchItem(id: "linearAccount", title: "Linear Workspace", section: "Linear", tab: .accounts, keywords: ["connect linear", "teams", "workspace"]),
    SettingsSearchItem(id: "githubAccount", title: "GitHub Account", section: "GitHub", tab: .accounts, keywords: ["repositories", "connect github", "repos"]),

    SettingsSearchItem(id: "menuBarEventLeadTime", title: "Show title before", section: "Menu Bar Title", tab: .calendar, keywords: ["lead time", "upcoming meeting", "menu bar title", "event title"]),
    SettingsSearchItem(id: "menuBarEventPostStartGrace", title: "Show title after", section: "Menu Bar Title", tab: .calendar, keywords: ["grace", "meeting started", "menu bar title", "event title"]),
    SettingsSearchItem(id: "showsCalendarSection", title: "Show calendar in menu", section: "Menu", tab: .calendar, keywords: ["calendar section", "events in menu"]),
    SettingsSearchItem(id: "showsLinearSection", title: "Show issues in menu", section: "Menu", tab: .issues, keywords: ["issues section", "linear section", "tickets in menu"]),
    SettingsSearchItem(id: "showsNotesSection", title: "Show notes in menu", section: "Menu", tab: .notes, keywords: ["notes section"]),

    SettingsSearchItem(id: "showsCalendarSourceNames", title: "Show calendar names", section: "Menu", tab: .calendar, keywords: ["source names", "account names"]),
    SettingsSearchItem(id: "meetingAlertEnabled", title: "Full-screen meeting alerts", section: "Meeting Alerts", tab: .calendar, keywords: ["alert", "reminder", "notification"]),
    SettingsSearchItem(id: "meetingAlertLead", title: "Show alert", section: "Meeting Alerts", tab: .calendar, keywords: ["alert lead", "minutes before", "reminder"]),

    SettingsSearchItem(id: "linearCreateDefaultTeam", title: "Default team", section: "New Linear Issue Defaults", tab: .issues, keywords: ["linear defaults", "new issue"]),
    SettingsSearchItem(id: "linearCreateDefaultStatus", title: "Default status", section: "New Linear Issue Defaults", tab: .issues, keywords: ["linear defaults", "new issue", "workflow state"]),
    SettingsSearchItem(id: "linearCreateDefaultPriority", title: "Default priority", section: "New Linear Issue Defaults", tab: .issues, keywords: ["linear defaults", "new issue", "urgent"]),
    SettingsSearchItem(id: "linearCreateDefaultProject", title: "Default project", section: "New Linear Issue Defaults", tab: .issues, keywords: ["linear defaults", "new issue"]),
    SettingsSearchItem(id: "linearCreateDefaultLabel", title: "Default label", section: "New Linear Issue Defaults", tab: .issues, keywords: ["linear defaults", "new issue", "tag"]),
    SettingsSearchItem(id: "githubCreateDefaultRepo", title: "Default repository", section: "New GitHub Issue Defaults", tab: .issues, keywords: ["github defaults", "new issue", "repo"]),
    SettingsSearchItem(id: "linearIssueOrder", title: "Linear issue order", section: "Menu", tab: .issues, keywords: ["sort issues", "issue sorting", "linear order"]),
    SettingsSearchItem(id: "linearIssueFilter", title: "Linear issues", section: "Shown Issues", tab: .issues, keywords: ["assigned to me", "all open issues", "filter", "issue filter"]),
    SettingsSearchItem(id: "githubIssueFilter", title: "GitHub issues", section: "Shown Issues", tab: .issues, keywords: ["assigned to me", "all open issues", "filter", "issue filter"]),

    SettingsSearchItem(id: "defaultNoteCount", title: "Notes shown", section: "Menu", tab: .notes, keywords: ["note count", "number of notes"]),
    SettingsSearchItem(id: "localNoteSortOrder", title: "Notes sort", section: "Menu", tab: .notes, keywords: ["note order", "sort notes"]),

    SettingsSearchItem(id: "copyIssueHotkey", title: "Copy issue/meeting link", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["hotkey", "copy link", "hover"]),
    SettingsSearchItem(id: "linearCopyStyle", title: "Issue copy target", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["copy style", "url", "identifier", "title"]),
    SettingsSearchItem(id: "statusPickerHotkey", title: "Change status", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "status"]),
    SettingsSearchItem(id: "priorityPickerHotkey", title: "Change priority", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "priority"]),
    SettingsSearchItem(id: "dueDatePickerHotkey", title: "Change due date", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "deadline", "due date"]),
    SettingsSearchItem(id: "labelPickerHotkey", title: "Change labels", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "tags", "labels"]),
    SettingsSearchItem(id: "assigneePickerHotkey", title: "Change assignees", section: "Hover Shortcuts", tab: .shortcuts, keywords: ["hotkey", "hover", "assign"]),
    SettingsSearchItem(id: "newNoteShortcut", title: "New note", section: "Global Shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "note"]),
    SettingsSearchItem(id: "newLinearIssueShortcut", title: "New Linear issue", section: "Global Shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "issue"]),
    SettingsSearchItem(id: "newGitHubIssueShortcut", title: "New GitHub issue", section: "Global Shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "issue", "github"]),
    SettingsSearchItem(id: "openGoogleCalendarShortcut", title: "Open Google Calendar", section: "Global Shortcuts", tab: .shortcuts, keywords: ["hotkey", "keyboard shortcut", "global", "calendar"]),
  ]
}
