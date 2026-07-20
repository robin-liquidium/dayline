import Foundation

/// Deterministic-looking sample data used by the isolated screenshot build.
struct MockData {
  let availableUpdateVersion: String?
  let events: [CalendarEventItem]
  let tomorrowEvents: [CalendarEventItem]
  let issues: [LinearIssueItem]
  let notes: [LocalNoteItem]
  let connectionStatuses: [ConnectionStatus]
  let googleAccounts: [GoogleAccountStatus]
  let teams: [LinearTeamOption]
  let users: [LinearUserOption]

  static func make(now: Date = Date()) -> MockData {
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    let workflowStates = [
      LinearWorkflowState(id: "mock-backlog", name: "Backlog", type: "backlog", position: 0),
      LinearWorkflowState(id: "mock-todo", name: "Todo", type: "unstarted", position: 1),
      LinearWorkflowState(id: "mock-progress", name: "In Progress", type: "started", position: 2),
      LinearWorkflowState(id: "mock-review", name: "In Review", type: "started", position: 3),
      LinearWorkflowState(id: "mock-done", name: "Done", type: "completed", position: 4),
      LinearWorkflowState(id: "mock-canceled", name: "Canceled", type: "canceled", position: 5)
    ]

    func event(
      _ id: String,
      _ title: String,
      startsIn minutes: Int,
      duration: Int,
      location: String? = nil,
      source: String = "Work"
    ) -> CalendarEventItem {
      let startDate = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
      let endDate = calendar.date(byAdding: .minute, value: duration, to: startDate) ?? startDate
      return CalendarEventItem(
        id: id,
        title: title,
        startDate: startDate,
        endDate: endDate,
        location: location,
        calendarURL: URL(string: "https://calendar.google.com"),
        openURL: URL(string: "https://meet.google.com/mock-dayline-demo"),
        sourceCalendarNames: [source],
        deduplicationKey: "mock-\(id)"
      )
    }

    func issue(
      _ id: String,
      _ title: String,
      priority: Int,
      priorityLabel: String,
      stateID: String,
      stateName: String,
      stateType: String,
      dueInDays: Int? = nil
    ) -> LinearIssueItem {
      let dueDate = dueInDays.flatMap { days -> String? in
        guard let date = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
      }
      return LinearIssueItem(
        id: id,
        title: title,
        priority: priority,
        priorityLabel: priorityLabel,
        stateName: stateName,
        stateID: stateID,
        stateType: stateType,
        workflowStates: workflowStates,
        dueDate: dueDate,
        url: URL(string: "https://linear.app/dayline/issue/\(id.lowercased())")
      )
    }

    func note(_ id: String, _ text: String, updatedMinutesAgo: Int) -> LocalNoteItem {
      let updatedAt = calendar.date(byAdding: .minute, value: -updatedMinutesAgo, to: now) ?? now
      return LocalNoteItem(
        id: id,
        text: text,
        createdAt: calendar.date(byAdding: .day, value: -2, to: updatedAt) ?? updatedAt,
        updatedAt: updatedAt
      )
    }

    let issues = [
      issue("DAY-104", "Polish the onboarding checklist", priority: 1, priorityLabel: "Urgent", stateID: "mock-progress", stateName: "In Progress", stateType: "started", dueInDays: 0),
      issue("DAY-112", "Prepare launch screenshots", priority: 2, priorityLabel: "High", stateID: "mock-progress", stateName: "In Progress", stateType: "started", dueInDays: 1),
      issue("DAY-108", "Review homepage copy", priority: 2, priorityLabel: "High", stateID: "mock-todo", stateName: "Todo", stateType: "unstarted", dueInDays: 2),
      issue("DAY-117", "Fix reminder timezone edge case", priority: 3, priorityLabel: "Medium", stateID: "mock-review", stateName: "In Review", stateType: "started"),
      issue("DAY-115", "Add keyboard shortcut hints", priority: 3, priorityLabel: "Medium", stateID: "mock-todo", stateName: "Todo", stateType: "unstarted"),
      issue("DAY-119", "Write the next release notes", priority: 4, priorityLabel: "Low", stateID: "mock-todo", stateName: "Todo", stateType: "unstarted"),
      issue("DAY-121", "Investigate occasional sync delay", priority: 0, priorityLabel: "No priority", stateID: "mock-backlog", stateName: "Backlog", stateType: "backlog")
    ]

    let teams = [
      LinearTeamOption(id: "mock-team", key: "DAY", name: "Dayline", states: workflowStates)
    ]

    let workAccount = GoogleAccount(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      providerAccountID: "alex@company.com",
      displayLabel: "alex@company.com",
      calendars: [
        GoogleCalendarSource(id: "alex@company.com", name: "Work", isPrimary: true, isEnabled: true),
        GoogleCalendarSource(id: "team@company.com", name: "Product Team", isPrimary: false, isEnabled: true)
      ]
    )
    let personalAccount = GoogleAccount(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      providerAccountID: "alex@example.com",
      displayLabel: "alex@example.com",
      calendars: [
        GoogleCalendarSource(id: "alex@example.com", name: "Personal", isPrimary: true, isEnabled: true),
        GoogleCalendarSource(id: "birthdays", name: "Birthdays", isPrimary: false, isEnabled: false)
      ]
    )

    return MockData(
      availableUpdateVersion: "0.2.0",
      events: [
        event("mock-standup", "Product stand-up", startsIn: 30, duration: 25, source: "Product Team"),
        event("mock-design", "Design review", startsIn: 120, duration: 45, location: "Studio", source: "Work"),
        event("mock-focus", "Focus time", startsIn: 240, duration: 90, source: "Personal")
      ],
      tomorrowEvents: [
        event("mock-planning", "Weekly planning", startsIn: calendar.dateComponents([.minute], from: now, to: calendar.date(byAdding: .hour, value: 1, to: tomorrow) ?? tomorrow).minute ?? 0, duration: 45, source: "Work"),
        event("mock-coffee", "Coffee with Maya", startsIn: calendar.dateComponents([.minute], from: now, to: calendar.date(byAdding: .hour, value: 4, to: tomorrow) ?? tomorrow).minute ?? 0, duration: 45, location: "Juniper Cafe", source: "Personal")
      ],
      issues: issues,
      notes: [
        note("mock-note-1", "Landing page ideas\nTry a warmer background and keep the hero quiet.", updatedMinutesAgo: 8),
        note("mock-note-2", "Weekend plans\nHike, farmers market, do absolutely nothing.", updatedMinutesAgo: 42),
        note("mock-note-3", "Grocery list\nCoffee beans, lemons, pasta, good bread.", updatedMinutesAgo: 95),
        note("mock-note-4", "Books to read next\nThe Creative Act\nTomorrow, and Tomorrow, and Tomorrow", updatedMinutesAgo: 180)
      ],
      connectionStatuses: [
        ConnectionStatus(provider: .google, state: .connected, detail: nil, accountLabel: "2 accounts"),
        ConnectionStatus(provider: .linear, state: .connected, detail: nil, accountLabel: "Alex Morgan")
      ],
      googleAccounts: [
        GoogleAccountStatus(account: workAccount, state: .connected, detail: nil),
        GoogleAccountStatus(account: personalAccount, state: .connected, detail: nil)
      ],
      teams: teams,
      users: [
        LinearUserOption(id: "mock-user", name: "Alex Morgan", displayName: "alex", isActive: true)
      ]
    )
  }
}
