import AppKit
import Foundation

/// Main actor store that owns refreshed calendar and Linear state for the UI.
@MainActor
final class StatusStore: ObservableObject {
  /// Upcoming timed calendar events for today.
  @Published private(set) var events: [CalendarEventItem] = [] {
    didSet { updateMeetingAlert() }
  }

  /// Timed calendar events for tomorrow.
  @Published private(set) var tomorrowEvents: [CalendarEventItem] = []

  /// Highest priority active Linear issues assigned to the user.
  @Published private(set) var issues: [LinearIssueItem] = []

  /// Local notes persisted on this Mac.
  @Published private(set) var notes: [LocalNoteItem] = []

  /// Account- or calendar-scoped warnings that do not hide successful events.
  @Published private(set) var calendarWarnings: [String] = []

  /// Last successful raw per-calendar events used for immediate local recomputation.
  private var googleSourceEvents: [CalendarEventItem] = []

  /// Linear loading error shown as a compact status row.
  @Published private(set) var linearError: String?

  /// Linear workspace identity and locally selected teams.
  @Published private(set) var linearAccount = LinearAccount(workspaceName: "", userLabel: "", teams: [])

  /// Team discovery error shown in the expandable Linear account row.
  @Published private(set) var linearTeamError: String?

  /// Local notes persistence error shown as a compact status row.
  @Published private(set) var notesError: String?

  /// Open GitHub issues assigned to the user when GitHub is the issue source.
  @Published private(set) var githubIssues: [GitHubIssueItem] = []

  /// GitHub loading error shown as a compact status row.
  @Published private(set) var githubError: String?

  /// Repository discovery error shown in the expandable GitHub account row.
  @Published private(set) var githubRepositoryError: String?

  /// Accessible GitHub repositories and their local issue-list selections.
  @Published private(set) var githubAccount = GitHubAccount(repositories: [])

  /// Issues tab currently selected in the menu.
  @Published var issueSource: IssueSource {
    didSet {
      UserDefaults.standard.set(issueSource.rawValue, forKey: Self.issueSourceKey)
    }
  }

  /// Providers the user dismissed from the menu's setup section.
  @Published private(set) var dismissedProviders: Set<AuthProvider> {
    didSet {
      UserDefaults.standard.set(dismissedProviders.map(\.rawValue).sorted(), forKey: Self.dismissedProvidersKey)
    }
  }

  /// Connection state for Google and Linear accounts.
  @Published private(set) var connectionStatuses = ConnectionStatus.checkingAll

  /// Confirmation code shown while GitHub device authorization is pending.
  @Published private(set) var githubDeviceUserCode: String?

  /// Persisted Google accounts with their current runtime connection state.
  @Published private(set) var googleAccounts: [GoogleAccountStatus] = []

  /// Whether a Google browser authorization is currently in progress.
  @Published private(set) var isGoogleAuthorizationInProgress = false

  /// Compact error from the most recent add/reconnect attempt.
  @Published private(set) var googleAuthorizationError: String?

  /// Whether a refresh is currently running.
  @Published private(set) var isRefreshing = false

  /// Changes whenever a provider disconnects so in-flight results can be discarded.
  private var connectionRevisions: [AuthProvider: Int] = [:]

  /// Time when the last refresh completed successfully or partially.
  @Published private(set) var lastUpdatedAt: Date?

  /// Current clock tick used for menu bar countdown text.
  @Published private var menuBarClockDate = Date() {
    didSet { updateMeetingAlert() }
  }

  /// Identifier for the Linear issue currently under the pointer.
  @Published private(set) var hoveredIssueTarget: IssueActionTarget?

  /// Identifier for the local note currently under the pointer.
  @Published private(set) var hoveredNoteID: LocalNoteItem.ID?

  /// Identifier for the calendar event currently under the pointer.
  @Published private(set) var hoveredEventID: CalendarEventItem.ID?

  /// Identifier for the menu chrome control currently under the pointer.
  @Published private(set) var hoveredControlID: MenuControlID?

  /// Whether tomorrow's calendar events are visible.
  @Published private(set) var isTomorrowExpanded = false

  /// Identifier for the Linear issue whose URL was most recently copied.
  @Published private(set) var copiedIssueTarget: IssueActionTarget?

  /// Identifier for the calendar event whose link was most recently copied.
  @Published private(set) var copiedEventID: CalendarEventItem.ID?

  /// Identifier for the Linear issue whose status picker is open.
  @Published private(set) var statusPickerTarget: IssueActionTarget?

  /// Issue whose label picker is open.
  @Published private(set) var labelPickerTarget: IssueActionTarget?

  /// Issue whose assignee picker is open.
  @Published private(set) var assigneePickerTarget: IssueActionTarget?

  /// Identifier for the Linear issue whose priority picker is open.
  @Published private(set) var priorityPickerIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue whose due date picker is open.
  @Published private(set) var dueDatePickerIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue currently being updated.
  @Published private(set) var updatingIssueTarget: IssueActionTarget?

  /// Identifier for the Linear issue whose priority is currently being updated.
  @Published private(set) var updatingPriorityIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue whose due date is currently being updated.
  @Published private(set) var updatingDueDateIssueID: LinearIssueItem.ID?

  /// Number of sorted Linear issues currently shown in the menu.
  @Published private(set) var visibleIssueCount = initialVisibleIssueCount

  /// Number of sorted local notes currently shown in the menu.
  @Published private(set) var visibleNoteCount: Int

  /// Keyboard character used to copy the hovered Linear issue link.
  @Published private(set) var copyIssueHotkey: String {
    didSet {
      let normalizedHotkey = Self.normalizedHotkey(copyIssueHotkey, defaultValue: "c")
      guard copyIssueHotkey == normalizedHotkey else {
        copyIssueHotkey = normalizedHotkey
        return
      }
      UserDefaults.standard.set(copyIssueHotkey, forKey: Self.copyIssueHotkeyKey)
    }
  }

  /// Keyboard character used to open the hovered Linear issue status picker.
  @Published private(set) var statusPickerHotkey: String {
    didSet {
      let normalizedHotkey = Self.normalizedHotkey(statusPickerHotkey, defaultValue: "s")
      guard statusPickerHotkey == normalizedHotkey else {
        statusPickerHotkey = normalizedHotkey
        return
      }
      UserDefaults.standard.set(statusPickerHotkey, forKey: Self.statusPickerHotkeyKey)
    }
  }

  /// Keyboard character used to open the hovered Linear issue priority picker.
  @Published private(set) var priorityPickerHotkey: String {
    didSet {
      let normalizedHotkey = Self.normalizedHotkey(priorityPickerHotkey, defaultValue: "p")
      guard priorityPickerHotkey == normalizedHotkey else {
        priorityPickerHotkey = normalizedHotkey
        return
      }
      UserDefaults.standard.set(priorityPickerHotkey, forKey: Self.priorityPickerHotkeyKey)
    }
  }

  /// Keyboard character used to open the hovered Linear issue due date picker.
  @Published private(set) var dueDatePickerHotkey: String {
    didSet {
      let normalizedHotkey = Self.normalizedHotkey(dueDatePickerHotkey, defaultValue: "d")
      guard dueDatePickerHotkey == normalizedHotkey else {
        dueDatePickerHotkey = normalizedHotkey
        return
      }
      UserDefaults.standard.set(dueDatePickerHotkey, forKey: Self.dueDatePickerHotkeyKey)
    }
  }

  /// Keyboard character used to open the hovered issue label picker.
  @Published private(set) var labelPickerHotkey: String {
    didSet {
      let normalized = Self.normalizedHotkey(labelPickerHotkey, defaultValue: "l")
      guard labelPickerHotkey == normalized else { labelPickerHotkey = normalized; return }
      UserDefaults.standard.set(labelPickerHotkey, forKey: Self.labelPickerHotkeyKey)
    }
  }

  /// Keyboard character used to open the hovered issue assignee picker.
  @Published private(set) var assigneePickerHotkey: String {
    didSet {
      let normalized = Self.normalizedHotkey(assigneePickerHotkey, defaultValue: "a")
      guard assigneePickerHotkey == normalized else { assigneePickerHotkey = normalized; return }
      UserDefaults.standard.set(assigneePickerHotkey, forKey: Self.assigneePickerHotkeyKey)
    }
  }

  /// Whether calendar event rows show their source calendar names.
  @Published var showsCalendarSourceNames: Bool {
    didSet {
      UserDefaults.standard.set(showsCalendarSourceNames, forKey: Self.showsCalendarSourceNamesKey)
    }
  }

  /// Whether the calendar section appears in the menu bar popover.
  @Published var showsCalendarSection: Bool {
    didSet {
      UserDefaults.standard.set(showsCalendarSection, forKey: Self.showsCalendarSectionKey)
      updateMeetingAlert()
    }
  }

  /// Whether the Linear section appears in the menu bar popover.
  @Published var showsLinearSection: Bool {
    didSet {
      UserDefaults.standard.set(showsLinearSection, forKey: Self.showsLinearSectionKey)
    }
  }

  /// Whether the notes section appears in the menu bar popover.
  @Published var showsNotesSection: Bool {
    didSet {
      UserDefaults.standard.set(showsNotesSection, forKey: Self.showsNotesSectionKey)
    }
  }

  /// Whether a full-screen alert appears when a meeting starts.
  @Published var meetingAlertEnabled: Bool {
    didSet {
      UserDefaults.standard.set(meetingAlertEnabled, forKey: Self.meetingAlertEnabledKey)
      updateMeetingAlert()
    }
  }

  /// Minutes before a meeting starts when the full-screen alert may appear.
  @Published var meetingAlertLeadMinutes: Int {
    didSet {
      UserDefaults.standard.set(meetingAlertLeadMinutes, forKey: Self.meetingAlertLeadMinutesKey)
      updateMeetingAlert()
    }
  }

  /// Event currently presented by the full-screen meeting alert, if any.
  @Published private(set) var meetingAlertEvent: CalendarEventItem?

  /// Session-only set of events whose full-screen alert was dismissed.
  private var dismissedMeetingAlertEventIDs = Set<String>()

  /// What the copy shortcut places on the clipboard.
  @Published var linearCopyStyle: LinearCopyStyle {
    didSet {
      UserDefaults.standard.set(linearCopyStyle.rawValue, forKey: Self.linearCopyStyleKey)
    }
  }

  /// User-selected ordering for Linear issues.
  @Published var linearIssueOrder: LinearIssueOrder {
    didSet {
      UserDefaults.standard.set(linearIssueOrder.rawValue, forKey: Self.linearIssueOrderKey)
      applyLinearIssueOrder()
    }
  }

  /// Which Linear issues appear in the menu.
  @Published private(set) var linearIssueFilter: IssueAssigneeFilter

  /// Which GitHub issues appear in the menu.
  @Published private(set) var githubIssueFilter: IssueAssigneeFilter

  /// Repository preselected when opening the GitHub issue creator.
  @Published var githubIssueCreateDefaultRepo: String {
    didSet {
      UserDefaults.standard.set(githubIssueCreateDefaultRepo, forKey: Self.githubIssueCreateDefaultRepoKey)
    }
  }

  /// Team preselected when opening the Linear issue creator.
  @Published var linearIssueCreateDefaultTeamID: String {
    didSet {
      UserDefaults.standard.set(linearIssueCreateDefaultTeamID, forKey: Self.linearIssueCreateDefaultTeamIDKey)
    }
  }

  /// Workflow state preselected when opening the Linear issue creator.
  @Published var linearIssueCreateDefaultStateID: String {
    didSet {
      UserDefaults.standard.set(linearIssueCreateDefaultStateID, forKey: Self.linearIssueCreateDefaultStateIDKey)
    }
  }

  /// Priority preselected when opening the Linear issue creator.
  @Published var linearIssueCreateDefaultPriority: Int {
    didSet {
      UserDefaults.standard.set(linearIssueCreateDefaultPriority, forKey: Self.linearIssueCreateDefaultPriorityKey)
    }
  }

  /// Project preselected when opening the Linear issue creator.
  @Published var linearIssueCreateDefaultProjectID: String {
    didSet {
      UserDefaults.standard.set(linearIssueCreateDefaultProjectID, forKey: Self.linearIssueCreateDefaultProjectIDKey)
    }
  }

  /// Label preselected when opening the Linear issue creator.
  @Published var linearIssueCreateDefaultLabelID: String {
    didSet {
      UserDefaults.standard.set(linearIssueCreateDefaultLabelID, forKey: Self.linearIssueCreateDefaultLabelIDKey)
    }
  }

  /// User-selected ordering for local notes.
  @Published var localNoteSortOrder: LocalNoteSortOrder {
    didSet {
      UserDefaults.standard.set(localNoteSortOrder.rawValue, forKey: Self.localNoteSortOrderKey)
      applyLocalNoteSortOrder()
    }
  }

  /// User-selected number of notes shown before expansion.
  @Published var defaultVisibleNoteCount: Int {
    didSet {
      let clampedCount = Self.clampedDefaultVisibleNoteCount(defaultVisibleNoteCount)
      guard defaultVisibleNoteCount == clampedCount else {
        defaultVisibleNoteCount = clampedCount
        return
      }
      UserDefaults.standard.set(defaultVisibleNoteCount, forKey: Self.defaultVisibleNoteCountKey)
      visibleNoteCount = defaultVisibleNoteCount
      applyLocalNoteSortOrder()
    }
  }

  /// Refresh cadence in minutes, persisted in user defaults.
  @Published var refreshIntervalMinutes: Int {
    didSet {
      guard refreshIntervalMinutes >= 1 else {
        refreshIntervalMinutes = 1
        return
      }
      UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
      scheduleRefreshTimer()
    }
  }

  /// Minutes before a meeting starts when the menu bar switches from icon to title.
  @Published var menuBarEventLeadTimeMinutes: Int {
    didSet {
      let clampedValue = Self.clampedMenuBarLeadTime(menuBarEventLeadTimeMinutes)
      guard menuBarEventLeadTimeMinutes == clampedValue else {
        menuBarEventLeadTimeMinutes = clampedValue
        return
      }
      UserDefaults.standard.set(menuBarEventLeadTimeMinutes, forKey: Self.menuBarEventLeadTimeKey)
    }
  }

  /// Minutes after a meeting starts when the menu bar keeps showing the title.
  @Published var menuBarEventPostStartGraceMinutes: Int {
    didSet {
      let clampedValue = Self.clampedMenuBarPostStartGrace(menuBarEventPostStartGraceMinutes)
      guard menuBarEventPostStartGraceMinutes == clampedValue else {
        menuBarEventPostStartGraceMinutes = clampedValue
        return
      }
      UserDefaults.standard.set(menuBarEventPostStartGraceMinutes, forKey: Self.menuBarEventPostStartGraceKey)
    }
  }

  /// Whether macOS launches Dayline when the user logs in.
  @Published private(set) var launchAtLoginEnabled: Bool

  /// Compact error text from the last launch-at-login update attempt.
  @Published private(set) var launchAtLoginError: String?

  /// Registration error for the most recently rejected global shortcut.
  @Published private(set) var globalShortcutError: String?

  /// Changes when an app-level flow needs to present the Settings window.
  @Published private(set) var settingsPresentationRequestID = UUID()

  /// Global shortcut that creates a new note from anywhere.
  @Published private(set) var newNoteShortcut: GlobalShortcut

  /// Global shortcut that opens the Linear issue creator from anywhere.
  @Published private(set) var newLinearIssueShortcut: GlobalShortcut

  /// Global shortcut that opens Google Calendar from anywhere.
  @Published private(set) var openGoogleCalendarShortcut: GlobalShortcut

  /// Global shortcut that opens the GitHub issue creator from anywhere.
  @Published private(set) var newGitHubIssueShortcut: GlobalShortcut

  /// Changes when a global hotkey needs to present a new note editor.
  @Published private(set) var noteCreationRequestID = UUID()

  /// Changes when a global hotkey needs to present the Linear issue creator.
  @Published private(set) var linearIssueCreationRequestID = UUID()

  /// Changes when a global hotkey needs to present the GitHub issue creator.
  @Published private(set) var githubIssueCreationRequestID = UUID()

  /// Stable system image for the menu bar item.
  var menuBarSystemImage: String {
    "calendar"
  }

  /// Optional text that replaces the menu bar icon near a meeting start.
  var menuBarEventText: String? {
    guard isCalendarSectionVisible, let event = menuBarEvent(at: menuBarClockDate) else {
      return nil
    }

    let startLabel = DisplayFormatters.menuBarEventStart(event.startDate, now: menuBarClockDate)
    return "\(event.title.compactLine(limit: 44)) • \(startLabel)"
  }

  /// VoiceOver label for the current menu bar presentation.
  var menuBarAccessibilityLabel: String {
    menuBarEventText ?? "Dayline"
  }

  /// Current lightweight clock tick used by views that need live calendar state.
  var calendarHighlightDate: Date {
    menuBarClockDate
  }

  private static let initialVisibleIssueCount = 6
  private static let issuePageSize = 10
  private static let refreshIntervalKey = "refreshIntervalMinutes"
  private static let copyIssueHotkeyKey = "copyIssueHotkey"
  private static let statusPickerHotkeyKey = "statusPickerHotkey"
  private static let priorityPickerHotkeyKey = "priorityPickerHotkey"
  private static let dueDatePickerHotkeyKey = "dueDatePickerHotkey"
  private static let labelPickerHotkeyKey = "labelPickerHotkey"
  private static let assigneePickerHotkeyKey = "assigneePickerHotkey"
  private static let showsCalendarSourceNamesKey = "showsCalendarSourceNames"
  private static let showsCalendarSectionKey = "showsCalendarSection"
  private static let showsLinearSectionKey = "showsLinearSection"
  private static let showsNotesSectionKey = "showsNotesSection"
  private static let meetingAlertEnabledKey = "meetingAlertEnabled"
  private static let meetingAlertLeadMinutesKey = "meetingAlertLeadMinutes"
  private static let issueSourceKey = "issueSource"
  private static let dismissedProvidersKey = "dismissedProviders"
  private static let linearIssueOrderKey = "linearIssueOrder"
  private static let linearCopyStyleKey = "linearCopyStyle"
  private static let linearIssueFilterKey = "linearIssueFilter"
  private static let githubIssueFilterKey = "githubIssueFilter"
  private static let githubIssueCreateDefaultRepoKey = "githubIssueCreateDefaultRepo"
  private static let linearIssueCreateDefaultTeamIDKey = "linearIssueCreateDefaultTeamID"
  private static let linearIssueCreateDefaultStateIDKey = "linearIssueCreateDefaultStateID"
  private static let linearIssueCreateDefaultPriorityKey = "linearIssueCreateDefaultPriority"
  private static let linearIssueCreateDefaultProjectIDKey = "linearIssueCreateDefaultProjectID"
  private static let linearIssueCreateDefaultLabelIDKey = "linearIssueCreateDefaultLabelID"
  private static let localNoteSortOrderKey = "localNoteSortOrder"
  private static let defaultVisibleNoteCountKey = "defaultVisibleNoteCount"
  private static let menuBarEventLeadTimeKey = "menuBarEventLeadTimeMinutes"
  private static let menuBarEventPostStartGraceKey = "menuBarEventPostStartGraceMinutes"
  private static let launchAtLoginDefaultConfiguredKey = "launchAtLoginDefaultConfigured"
  private static let launchAtLoginDefaultPendingKey = "launchAtLoginDefaultPending"
  private static let newNoteShortcutKey = "newNoteGlobalShortcut"
  private static let newLinearIssueShortcutKey = "newLinearIssueGlobalShortcut"
  private static let openGoogleCalendarShortcutKey = "openGoogleCalendarGlobalShortcut"
  private static let newGitHubIssueShortcutKey = "newGitHubIssueGlobalShortcut"
  private static let defaultMenuBarEventLeadTimeMinutes = 30
  private static let defaultMenuBarEventPostStartGraceMinutes = 0
  private static let fallbackDefaultVisibleNoteCount = 3
  private static let menuBarClockRefreshSeconds: TimeInterval = 15
  /// Post-start window during which the full-screen meeting alert may still appear.
  private static let meetingAlertPostStartGrace: TimeInterval = 10 * 60
  private static let todayEventLimit = 6
  private static let tomorrowEventLimit = 8

  private let linearService: LinearService
  private let githubService = GitHubService()
  private let githubAuth = GitHubDeviceAuthService.shared
  private let notesService: LocalNotesService
  private let authSessions: [AuthProvider: OAuthSession]
  private let googleAccountRepository: GoogleAccountRepository
  private let linearAccountRepository: LinearAccountRepository
  private let githubAccountRepository: GitHubAccountRepository
  private let launchAtLoginService: LaunchAtLoginService
  private let globalHotkeyService = GlobalHotkeyService()
  private let mockData: MockData?
  private var googleSessions: [UUID: OAuthSession] = [:]
  private var allIssues: [LinearIssueItem] = []
  private var allNotes: [LocalNoteItem] = []
  private var optimisticGitHubIssues: [(issue: GitHubIssueItem, insertedAt: Date)] = []
  private var refreshTimer: Timer?
  private var menuBarClockTimer: Timer?
  private var refreshRequested = false

  /// Creates a live store and immediately starts the background refresh loop.
  init(
    linearService: LinearService = LinearService(),
    notesService: LocalNotesService = LocalNotesService(),
    authSessions: [AuthProvider: OAuthSession] = [.linear: .linear],
    googleAccountRepository: GoogleAccountRepository = GoogleAccountRepository(),
    linearAccountRepository: LinearAccountRepository = LinearAccountRepository(),
    githubAccountRepository: GitHubAccountRepository = GitHubAccountRepository(),
    launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
    mockData: MockData? = nil
  ) {
    let defaults = UserDefaults.standard
    // Older builds stored no launch-at-login preference. Using that toggle required opening
    // Settings, which persists the Settings window frame, so an empty domain has no in-app
    // opt-out to preserve and should receive the new default.
    let hadPersistedAppState = Bundle.main.bundleIdentifier
      .flatMap { defaults.persistentDomain(forName: $0) }
      .map { !$0.isEmpty }
      ?? false
    self.linearService = linearService
    self.notesService = notesService
    self.authSessions = authSessions
    self.googleAccountRepository = googleAccountRepository
    self.linearAccountRepository = linearAccountRepository
    self.githubAccountRepository = githubAccountRepository
    self.launchAtLoginService = launchAtLoginService
    self.mockData = mockData
    self.refreshIntervalMinutes = defaults.integer(forKey: Self.refreshIntervalKey)
    let repairedHotkeys = Self.repairedHoverHotkeys(
      copy: defaults.string(forKey: Self.copyIssueHotkeyKey),
      status: defaults.string(forKey: Self.statusPickerHotkeyKey),
      priority: defaults.string(forKey: Self.priorityPickerHotkeyKey),
      dueDate: defaults.string(forKey: Self.dueDatePickerHotkeyKey),
      label: defaults.string(forKey: Self.labelPickerHotkeyKey),
      assignee: defaults.string(forKey: Self.assigneePickerHotkeyKey)
    )
    self.copyIssueHotkey = repairedHotkeys[0]
    self.statusPickerHotkey = repairedHotkeys[1]
    self.priorityPickerHotkey = repairedHotkeys[2]
    self.dueDatePickerHotkey = repairedHotkeys[3]
    self.labelPickerHotkey = repairedHotkeys[4]
    self.assigneePickerHotkey = repairedHotkeys[5]
    defaults.set(repairedHotkeys[0], forKey: Self.copyIssueHotkeyKey)
    defaults.set(repairedHotkeys[1], forKey: Self.statusPickerHotkeyKey)
    defaults.set(repairedHotkeys[2], forKey: Self.priorityPickerHotkeyKey)
    defaults.set(repairedHotkeys[3], forKey: Self.dueDatePickerHotkeyKey)
    defaults.set(repairedHotkeys[4], forKey: Self.labelPickerHotkeyKey)
    defaults.set(repairedHotkeys[5], forKey: Self.assigneePickerHotkeyKey)
    let noteShortcut = Self.loadShortcut(forKey: Self.newNoteShortcutKey, defaultValue: .newNoteDefault)
    let linearShortcut = Self.loadShortcut(forKey: Self.newLinearIssueShortcutKey, defaultValue: .newLinearIssueDefault)
    let requestedCalendarShortcut = Self.loadShortcut(
      forKey: Self.openGoogleCalendarShortcutKey,
      defaultValue: .openGoogleCalendarDefault
    )
    let calendarShortcut = [noteShortcut, linearShortcut].contains(requestedCalendarShortcut)
      ? GlobalShortcut.openGoogleCalendarFallbacks.first { ![noteShortcut, linearShortcut].contains($0) }
        ?? .openGoogleCalendarDefault
      : requestedCalendarShortcut
    self.newNoteShortcut = noteShortcut
    self.newLinearIssueShortcut = linearShortcut
    self.openGoogleCalendarShortcut = calendarShortcut
    Self.persistShortcut(calendarShortcut, forKey: Self.openGoogleCalendarShortcutKey)
    let requestedGitHubShortcut = Self.loadShortcut(
      forKey: Self.newGitHubIssueShortcutKey,
      defaultValue: .newGitHubIssueDefault
    )
    let otherShortcuts = [noteShortcut, linearShortcut, calendarShortcut]
    let githubShortcut = otherShortcuts.contains(requestedGitHubShortcut)
      ? GlobalShortcut.newGitHubIssueFallbacks.first { !otherShortcuts.contains($0) }
        ?? .newGitHubIssueDefault
      : requestedGitHubShortcut
    self.newGitHubIssueShortcut = githubShortcut
    Self.persistShortcut(githubShortcut, forKey: Self.newGitHubIssueShortcutKey)
    self.showsCalendarSourceNames = defaults.object(forKey: Self.showsCalendarSourceNamesKey) as? Bool ?? true
    self.showsCalendarSection = defaults.object(forKey: Self.showsCalendarSectionKey) as? Bool ?? true
    self.showsLinearSection = defaults.object(forKey: Self.showsLinearSectionKey) as? Bool ?? true
    self.showsNotesSection = defaults.object(forKey: Self.showsNotesSectionKey) as? Bool ?? true
    self.meetingAlertEnabled = defaults.object(forKey: Self.meetingAlertEnabledKey) as? Bool ?? true
    self.meetingAlertLeadMinutes = Self.storedInteger(forKey: Self.meetingAlertLeadMinutesKey, defaultValue: 0)
    self.issueSource = IssueSource(rawValue: defaults.string(forKey: Self.issueSourceKey) ?? "") ?? .linear
    self.dismissedProviders = Set(
      (defaults.stringArray(forKey: Self.dismissedProvidersKey) ?? []).compactMap(AuthProvider.init(rawValue:))
    )
    self.linearIssueOrder = LinearIssueOrder(rawValue: UserDefaults.standard.string(forKey: Self.linearIssueOrderKey) ?? "") ?? .priority
    self.linearCopyStyle = LinearCopyStyle(rawValue: UserDefaults.standard.string(forKey: Self.linearCopyStyleKey) ?? "") ?? .link
    self.linearIssueFilter = IssueAssigneeFilter(rawValue: defaults.string(forKey: Self.linearIssueFilterKey) ?? "") ?? .assignedToMe
    self.githubIssueFilter = IssueAssigneeFilter(rawValue: defaults.string(forKey: Self.githubIssueFilterKey) ?? "") ?? .assignedToMe
    self.githubIssueCreateDefaultRepo = defaults.string(forKey: Self.githubIssueCreateDefaultRepoKey) ?? ""
    self.linearIssueCreateDefaultTeamID = defaults.string(forKey: Self.linearIssueCreateDefaultTeamIDKey) ?? ""
    self.linearIssueCreateDefaultStateID = defaults.string(forKey: Self.linearIssueCreateDefaultStateIDKey) ?? ""
    self.linearIssueCreateDefaultPriority = Self.storedInteger(
      forKey: Self.linearIssueCreateDefaultPriorityKey,
      defaultValue: 0
    )
    self.linearIssueCreateDefaultProjectID = defaults.string(forKey: Self.linearIssueCreateDefaultProjectIDKey) ?? ""
    self.linearIssueCreateDefaultLabelID = defaults.string(forKey: Self.linearIssueCreateDefaultLabelIDKey) ?? ""
    self.localNoteSortOrder = LocalNoteSortOrder(rawValue: UserDefaults.standard.string(forKey: Self.localNoteSortOrderKey) ?? "") ?? .updatedAt
    let storedVisibleNoteCount = Self.clampedDefaultVisibleNoteCount(Self.storedInteger(
      forKey: Self.defaultVisibleNoteCountKey,
      defaultValue: Self.fallbackDefaultVisibleNoteCount
    ))
    self.defaultVisibleNoteCount = storedVisibleNoteCount
    self.visibleNoteCount = storedVisibleNoteCount
    self.launchAtLoginEnabled = mockData == nil ? launchAtLoginService.isEnabled : true
    self.menuBarEventLeadTimeMinutes = Self.storedInteger(
      forKey: Self.menuBarEventLeadTimeKey,
      defaultValue: Self.defaultMenuBarEventLeadTimeMinutes
    )
    self.menuBarEventPostStartGraceMinutes = Self.storedInteger(
      forKey: Self.menuBarEventPostStartGraceKey,
      defaultValue: Self.defaultMenuBarEventPostStartGraceMinutes
    )
    if refreshIntervalMinutes <= 0 {
      refreshIntervalMinutes = 15
    }
    menuBarEventLeadTimeMinutes = Self.clampedMenuBarLeadTime(menuBarEventLeadTimeMinutes)
    menuBarEventPostStartGraceMinutes = Self.clampedMenuBarPostStartGrace(menuBarEventPostStartGraceMinutes)
    if mockData == nil && defaults.object(forKey: Self.launchAtLoginDefaultConfiguredKey) == nil {
      let shouldApplyDefault = defaults.bool(forKey: Self.launchAtLoginDefaultPendingKey)
        || !hadPersistedAppState
      if shouldApplyDefault {
        defaults.set(true, forKey: Self.launchAtLoginDefaultPendingKey)
        do {
          try launchAtLoginService.setEnabled(true)
          launchAtLoginEnabled = launchAtLoginService.isEnabled
          if launchAtLoginEnabled {
            defaults.set(true, forKey: Self.launchAtLoginDefaultConfiguredKey)
            defaults.removeObject(forKey: Self.launchAtLoginDefaultPendingKey)
          }
        } catch {
          launchAtLoginError = error.localizedDescription.compactLine(limit: 96)
        }
      } else {
        // Existing installs predate this default; preserve their current login-item choice.
        defaults.set(true, forKey: Self.launchAtLoginDefaultConfiguredKey)
      }
    }
    if let mockData {
      applyMockData(mockData)
    } else {
      do {
        linearAccount = try linearAccountRepository.load()
      } catch {
        linearTeamError = error.localizedDescription
      }
      do {
        githubAccount = try githubAccountRepository.load()
      } catch {
        githubError = error.localizedDescription
      }
      do {
        googleAccounts = try googleAccountRepository.loadAndMigrateLegacyAccount().map {
          GoogleAccountStatus(account: $0, state: .checking, detail: nil)
        }
      } catch {
        googleAuthorizationError = error.localizedDescription
      }
      loadPersistedNotes()
      scheduleRefreshTimer()
      Task { await refresh() }
    }
    startGlobalHotkeys()
    scheduleMenuBarClockTimer()
  }

  deinit {
    refreshTimer?.invalidate()
    menuBarClockTimer?.invalidate()
  }

  /// Refreshes connection, calendar, and Linear data.
  func refresh() async {
    if let mockData {
      applyMockData(mockData)
      return
    }

    guard !isRefreshing else {
      refreshRequested = true
      return
    }

    isRefreshing = true
    await refreshConnectionStatus()
    let googleRevision = connectionRevisions[.google, default: 0]
    let linearRevision = connectionRevisions[.linear, default: 0]
    let githubRevision = connectionRevisions[.github, default: 0]

    let shouldLoadLinear = isConnected(.linear) && !dismissedProviders.contains(.linear)
    let shouldLoadGitHub = isConnected(.github) && !dismissedProviders.contains(.github)

    async let calendarResult: CalendarAgendaLoadResult? = hasConnectedGoogleAccount ? loadGoogleAgenda() : nil
    async let linearResult: Result<[LinearIssueItem], Error>? = shouldLoadLinear ? loadLinearIssues() : nil
    async let githubResult: Result<[GitHubIssueItem], Error>? = shouldLoadGitHub ? loadGitHubIssues() : nil

    let resolvedCalendarResult = await calendarResult
    if connectionRevisions[.google, default: 0] == googleRevision {
      if let calendarResult = resolvedCalendarResult {
        if calendarResult.shouldReplaceEvents {
          googleSourceEvents = calendarResult.sourceEvents
          events = calendarResult.today
          tomorrowEvents = calendarResult.tomorrow
        }
        calendarWarnings = calendarResult.warnings
        for accountID in calendarResult.reauthenticationAccountIDs {
          updateGoogleAccountStatus(
            accountID,
            state: .disconnected,
            detail: "Reconnect required."
          )
        }
        if !calendarResult.reauthenticationAccountIDs.isEmpty {
          updateGoogleAggregateStatus()
        }
      } else {
        googleSourceEvents = []
        events = []
        tomorrowEvents = []
        calendarWarnings = []
      }
    }

    switch await linearResult {
    case .success(let fetchedIssues)? where connectionRevisions[.linear, default: 0] == linearRevision && isConnected(.linear):
      allIssues = fetchedIssues
      applyLinearIssueOrder()
      linearError = nil
    case .failure(let error)? where connectionRevisions[.linear, default: 0] == linearRevision && isConnected(.linear):
      handleFetchFailure(error, for: .linear)
      linearError = error.localizedDescription
    case .some(_):
      break
    case nil:
      allIssues = []
      applyLinearIssueOrder()
      linearError = nil
    }

    switch await githubResult {
    case .success(let fetchedIssues)? where connectionRevisions[.github, default: 0] == githubRevision && isConnected(.github):
      let visibleIssues = fetchedIssues.filter { enabledGitHubRepositories.contains($0.repoFullName.lowercased()) }
      githubIssues = mergingOptimisticGitHubIssues(into: visibleIssues)
      githubError = nil
    case .failure(let error)? where connectionRevisions[.github, default: 0] == githubRevision && isConnected(.github):
      handleFetchFailure(error, for: .github)
      githubError = error.localizedDescription
    case .some(_):
      break
    case nil:
      githubIssues = []
      optimisticGitHubIssues = []
      githubError = nil
    }

    lastUpdatedAt = Date()
    isRefreshing = false
    if refreshRequested {
      refreshRequested = false
      await refresh()
    }
  }

  /// Rechecks stored credentials and refreshes each Google account's calendar catalog.
  func refreshConnectionStatus() async {
    if let mockData {
      connectionStatuses = mockData.connectionStatuses
      googleAccounts = mockData.googleAccounts
      return
    }

    let googleRevision = connectionRevisions[.google, default: 0]
    var refreshedGoogleAccounts: [GoogleAccountStatus] = []

    for status in googleAccounts {
      let session = googleSession(for: status.account)
      guard await session.hasTokens() else {
        refreshedGoogleAccounts.append(GoogleAccountStatus(
          account: status.account,
          state: .disconnected,
          detail: "Reconnect required."
        ))
        continue
      }

      do {
        let discovery = try await CalendarService(authSession: session).fetchAccountDiscovery()
        var account = status.account.reconcilingCalendars(discovery.calendars)
        account.providerAccountID = discovery.providerAccountID
        account.displayLabel = discovery.displayLabel
        refreshedGoogleAccounts.append(GoogleAccountStatus(account: account, state: .connected, detail: nil))
      } catch {
        let tokensRemain = await session.hasTokens()
        let needsReauthentication = requiresGoogleReauthentication(error) || !tokensRemain
        refreshedGoogleAccounts.append(GoogleAccountStatus(
          account: status.account,
          state: needsReauthentication ? .disconnected : .connected,
          detail: needsReauthentication
            ? "Reconnect required."
            : error.localizedDescription.compactLine(limit: 96)
        ))
      }
    }

    guard connectionRevisions[.google, default: 0] == googleRevision else {
      return
    }
    googleAccounts = refreshedGoogleAccounts
    persistGoogleAccounts()
    updateGoogleAggregateStatus()

    let linearRevision = connectionRevisions[.linear, default: 0]
    guard let linearSession = authSessions[.linear] else {
      updateConnectionStatus(.linear, state: .disconnected, detail: nil, accountLabel: nil)
      return
    }

    let hasLinearTokens = await linearSession.hasTokens()
    guard connectionRevisions[.linear, default: 0] == linearRevision else { return }
    if hasLinearTokens {
      var accountLabel = linearAccount.workspaceName.isEmpty
        ? connectionStatuses.first(where: { $0.provider == .linear })?.accountLabel
        : linearAccount.workspaceName
      do {
        let discovery = try await linearService.fetchAccountDiscovery()
        guard connectionRevisions[.linear, default: 0] == linearRevision else { return }
        linearAccount = linearAccount.reconciling(
          workspaceName: discovery.workspaceName,
          userLabel: discovery.userLabel,
          teams: discovery.teams
        )
        try linearAccountRepository.save(linearAccount)
        accountLabel = discovery.workspaceName
        linearTeamError = nil
      } catch {
        linearTeamError = "Team discovery failed: \(error.localizedDescription)"
      }
      guard connectionRevisions[.linear, default: 0] == linearRevision else { return }
      updateConnectionStatus(.linear, state: .connected, detail: nil, accountLabel: accountLabel)
    } else {
      let detail = AuthProvider.linear.isConfigured ? nil : "This build is missing its OAuth client ID."
      updateConnectionStatus(.linear, state: .disconnected, detail: detail, accountLabel: nil)
    }

    let githubRevision = connectionRevisions[.github, default: 0]
    if await githubAuth.hasToken() {
      let previousLabel = connectionStatuses.first(where: { $0.provider == .github })?.accountLabel
      let accountLabel: String?
      if let previousLabel {
        accountLabel = previousLabel
      } else {
        accountLabel = try? await githubService.fetchAccountLabel()
      }
      guard connectionRevisions[.github, default: 0] == githubRevision else { return }
      updateConnectionStatus(.github, state: .connected, detail: nil, accountLabel: accountLabel)
      do {
        let discovered = try await githubService.fetchRepositories()
        guard connectionRevisions[.github, default: 0] == githubRevision else { return }
        githubAccount = githubAccount.reconcilingRepositories(discovered)
        try githubAccountRepository.save(githubAccount)
        githubRepositoryError = nil
      } catch {
        githubRepositoryError = "Repository discovery failed: \(error.localizedDescription)"
      }
    } else {
      let currentState = connectionStatuses.first(where: { $0.provider == .github })?.state
      if currentState != .connecting {
        let detail = AuthProvider.github.isConfigured ? nil : "This build is missing its OAuth client ID."
        updateConnectionStatus(.github, state: .disconnected, detail: detail, accountLabel: nil)
      }
    }
  }

  /// Providers that still need the user to connect an account.
  var connectionSetupItems: [ConnectionStatus] {
    connectionStatuses.filter { status in
      guard isSectionEnabled(for: status.provider) else { return false }
      guard !dismissedProviders.contains(status.provider) else { return false }
      return status.state != .connected && (status.provider != .google || googleAccounts.isEmpty)
    }
  }

  /// Issue providers that are connected and have not been dismissed by the user.
  var availableIssueSources: [IssueSource] {
    IssueSource.allCases.filter { source in
      let provider: AuthProvider = source == .linear ? .linear : .github
      return isConnected(provider) && !dismissedProviders.contains(provider)
    }
  }

  /// Issue source currently shown in the menu, repaired when its provider is unavailable.
  var activeIssueSource: IssueSource? {
    let sources = availableIssueSources
    if sources.contains(issueSource) {
      return issueSource
    }
    return sources.first
  }

  /// Whether the calendar section should appear in the menu bar popover.
  var isCalendarSectionVisible: Bool {
    showsCalendarSection && !dismissedProviders.contains(.google)
  }

  /// Whether the issues section should appear in the menu bar popover.
  var isIssuesSectionVisible: Bool {
    showsLinearSection && activeIssueSource != nil
  }

  /// Whether one provider was dismissed from the menu's setup section.
  func isProviderDismissed(_ provider: AuthProvider) -> Bool {
    dismissedProviders.contains(provider)
  }

  /// Dismisses one provider's setup prompt and hides its menu content until it connects.
  func dismissProvider(_ provider: AuthProvider) {
    dismissedProviders.insert(provider)
  }

  /// Restores one provider's menu content after a successful connection.
  private func undismissProvider(_ provider: AuthProvider) {
    dismissedProviders.remove(provider)
  }

  /// Whether the menu section tied to a provider is enabled.
  private func isSectionEnabled(for provider: AuthProvider) -> Bool {
    switch provider {
    case .google:
      showsCalendarSection
    case .linear, .github:
      showsLinearSection
    }
  }

  /// Existing Google accounts that need account-specific reauthentication.
  var googleAccountsNeedingAttention: [GoogleAccountStatus] {
    guard isCalendarSectionVisible else { return [] }
    return googleAccounts.filter(\.needsAttention)
  }

  /// Whether another Google authorization can begin without duplicating a migrated placeholder.
  var canAddGoogleAccount: Bool {
    !isGoogleAuthorizationInProgress
      && !googleAccounts.contains { $0.account.providerAccountID == nil }
  }

  /// Whether the setup section should be visible.
  var hasConnectionSetupItems: Bool {
    !connectionSetupItems.isEmpty || !googleAccountsNeedingAttention.isEmpty
  }

  /// Starts the browser sign-in flow for one provider.
  func connect(_ provider: AuthProvider) async {
    guard mockData == nil else { return }

    if provider == .google {
      await addGoogleAccount()
      return
    }

    if provider == .github {
      await connectGitHub()
      return
    }

    guard let session = authSessions[provider],
          connectionStatuses.first(where: { $0.provider == provider })?.state != .connecting else {
      return
    }
    connectionRevisions[provider, default: 0] += 1
    let revision = connectionRevisions[provider, default: 0]

    updateConnectionStatus(
      provider,
      state: .connecting,
      detail: "Finish sign-in in your browser.",
      accountLabel: nil
    )

    do {
      try await session.signIn()
      guard connectionRevisions[provider, default: 0] == revision else { return }
      let accountLabel = try? await fetchAccountLabel(for: provider)
      guard connectionRevisions[provider, default: 0] == revision else { return }
      updateConnectionStatus(provider, state: .connected, detail: nil, accountLabel: accountLabel)
      undismissProvider(provider)
      await refresh()
      guard connectionRevisions[provider, default: 0] == revision else { return }
      presentSettingsAfterAuth()
    } catch OAuthError.authorizationCancelled {
      guard connectionRevisions[provider, default: 0] == revision else { return }
      updateConnectionStatus(provider, state: .disconnected, detail: nil, accountLabel: nil)
    } catch {
      guard connectionRevisions[provider, default: 0] == revision else { return }
      updateConnectionStatus(
        provider,
        state: .disconnected,
        detail: error.localizedDescription.compactLine(limit: 96),
        accountLabel: nil
      )
    }
  }

  /// Runs the GitHub device authorization flow and connects on success.
  private func connectGitHub() async {
    guard connectionStatuses.first(where: { $0.provider == .github })?.state != .connecting else {
      return
    }
    connectionRevisions[.github, default: 0] += 1
    let revision = connectionRevisions[.github, default: 0]
    githubDeviceUserCode = nil

    updateConnectionStatus(.github, state: .connecting, detail: "Requesting device code...", accountLabel: nil)

    do {
      let code = try await githubAuth.beginSignIn()
      guard connectionRevisions[.github, default: 0] == revision else { return }
      NSWorkspace.shared.open(code.verificationURI)
      githubDeviceUserCode = code.userCode
      updateConnectionStatus(
        .github,
        state: .connecting,
        detail: "Enter code \(code.userCode) on the GitHub page that just opened.",
        accountLabel: nil
      )
      try await githubAuth.pollForAuthorization(code)
      guard connectionRevisions[.github, default: 0] == revision else { return }
      let accountLabel = try? await githubService.fetchAccountLabel()
      guard connectionRevisions[.github, default: 0] == revision else { return }
      githubDeviceUserCode = nil
      updateConnectionStatus(.github, state: .connected, detail: nil, accountLabel: accountLabel)
      undismissProvider(.github)
      await refresh()
      guard connectionRevisions[.github, default: 0] == revision else { return }
      presentSettingsAfterAuth()
    } catch {
      guard connectionRevisions[.github, default: 0] == revision else { return }
      githubDeviceUserCode = nil
      updateConnectionStatus(
        .github,
        state: .disconnected,
        detail: error.localizedDescription.compactLine(limit: 96),
        accountLabel: nil
      )
    }
  }

  /// Cancels an in-progress connection attempt for one provider.
  func cancelConnect(_ provider: AuthProvider) {
    guard mockData == nil else { return }

    connectionRevisions[provider, default: 0] += 1

    switch provider {
    case .github:
      githubDeviceUserCode = nil
      Task {
        await githubAuth.cancelSignIn()
        await githubAuth.signOut()
      }
      updateConnectionStatus(.github, state: .disconnected, detail: nil, accountLabel: nil)
    case .google:
      BrowserOAuthCoordinator.shared.cancel()
      isGoogleAuthorizationInProgress = false
      googleAuthorizationError = nil
      for accountID in googleAccounts.filter({ $0.state == .connecting }).map(\.id) {
        updateGoogleAccountStatus(accountID, state: .disconnected, detail: "Reconnect required.")
      }
      updateGoogleAggregateStatus()
    case .linear:
      BrowserOAuthCoordinator.shared.cancel()
      updateConnectionStatus(provider, state: .disconnected, detail: nil, accountLabel: nil)
    }
  }

  /// Revokes and removes the stored credentials for one provider.
  func disconnect(_ provider: AuthProvider) async {
    guard mockData == nil else { return }

    if provider == .google {
      for account in googleAccounts {
        await disconnectGoogleAccount(account.id)
      }
      return
    }

    if provider == .github {
      connectionRevisions[.github, default: 0] += 1
      githubDeviceUserCode = nil
      await githubAuth.cancelSignIn()
      await githubAuth.signOut()
      updateConnectionStatus(.github, state: .disconnected, detail: nil, accountLabel: nil)
      githubIssues = []
      optimisticGitHubIssues = []
      githubError = nil
      return
    }

    guard let session = authSessions[provider] else {
      return
    }

    connectionRevisions[provider, default: 0] += 1
    await session.signOut()
    updateConnectionStatus(provider, state: .disconnected, detail: nil, accountLabel: nil)

    allIssues = []
    applyLinearIssueOrder()
    linearError = nil
  }

  /// Links a new Google account or refreshes credentials for an already-linked identity.
  func addGoogleAccount() async {
    guard canAddGoogleAccount else { return }
    await authorizeGoogleAccount(reconnecting: nil)
  }

  /// Reauthenticates one existing Google account without allowing an identity swap.
  func reconnectGoogleAccount(_ accountID: UUID) async {
    guard let status = googleAccounts.first(where: { $0.id == accountID }) else { return }
    await authorizeGoogleAccount(reconnecting: status.account)
  }

  /// Revokes and removes one Google account while retaining all other accounts.
  func disconnectGoogleAccount(_ accountID: UUID) async {
    guard mockData == nil,
          let index = googleAccounts.firstIndex(where: { $0.id == accountID }) else {
      return
    }

    connectionRevisions[.google, default: 0] += 1
    let account = googleAccounts[index].account
    await googleSession(for: account).signOut()
    guard let removalIndex = googleAccounts.firstIndex(where: { $0.id == accountID }) else {
      return
    }
    googleAccounts.remove(at: removalIndex)
    connectionRevisions[.google, default: 0] += 1
    googleSessions[accountID] = nil
    let accountPrefix = "\(accountID.uuidString)|"
    googleSourceEvents.removeAll { event in
      event.sourceIDs.contains { $0.hasPrefix(accountPrefix) }
    }
    rebuildAgendaFromCachedGoogleSources()
    calendarWarnings = []
    googleAuthorizationError = nil
    persistGoogleAccounts()
    updateGoogleAggregateStatus()
    await refresh()
  }

  /// Updates one calendar checkbox and immediately recomputes the merged agenda.
  func setGoogleCalendarEnabled(accountID: UUID, calendarID: String, isEnabled: Bool) {
    guard let accountIndex = googleAccounts.firstIndex(where: { $0.id == accountID }),
          let calendarIndex = googleAccounts[accountIndex].account.calendars.firstIndex(where: { $0.id == calendarID }) else {
      return
    }

    googleAccounts[accountIndex].account.calendars[calendarIndex].isEnabled = isEnabled
    connectionRevisions[.google, default: 0] += 1
    if !isEnabled {
      let disabledSourceID = CalendarEventItem.sourceID(accountID: accountID, calendarID: calendarID)
      googleSourceEvents.removeAll { $0.sourceIDs.contains(disabledSourceID) }
      rebuildAgendaFromCachedGoogleSources()
      calendarWarnings = []
    }
    persistGoogleAccounts()
    Task { await refresh() }
  }

  /// Updates one Linear team checkbox and immediately refreshes the assigned issue list.
  func setLinearTeamEnabled(teamID: String, isEnabled: Bool) {
    guard let index = linearAccount.teams.firstIndex(where: { $0.id == teamID }) else { return }
    linearAccount.teams[index].isEnabled = isEnabled
    do {
      try linearAccountRepository.save(linearAccount)
      allIssues.removeAll { !enabledLinearTeamIDs.contains($0.teamID) }
      applyLinearIssueOrder()
      linearTeamError = nil
      Task { await refresh() }
    } catch {
      linearTeamError = error.localizedDescription
    }
  }

  private var enabledLinearTeamIDs: Set<String> {
    Set(linearAccount.teams.filter(\.isEnabled).map(\.id))
  }

  /// Persists which Linear issues appear in the menu and refreshes the list.
  func setLinearIssueFilter(_ filter: IssueAssigneeFilter) {
    guard filter != linearIssueFilter else { return }
    linearIssueFilter = filter
    UserDefaults.standard.set(filter.rawValue, forKey: Self.linearIssueFilterKey)
    Task { await refresh() }
  }

  /// Persists which GitHub issues appear in the menu and refreshes the list.
  func setGitHubIssueFilter(_ filter: IssueAssigneeFilter) {
    guard filter != githubIssueFilter else { return }
    githubIssueFilter = filter
    UserDefaults.standard.set(filter.rawValue, forKey: Self.githubIssueFilterKey)
    Task { await refresh() }
  }

  private var linearIssueTeamFilter: Set<String>? {
    linearAccount.hasDiscoveredTeams ? enabledLinearTeamIDs : nil
  }

  /// Updates one GitHub repository checkbox and immediately refreshes the issue list.
  func setGitHubRepositoryEnabled(fullName: String, isEnabled: Bool) {
    guard let index = githubAccount.repositories.firstIndex(where: { $0.fullName == fullName }) else { return }
    githubAccount.repositories[index].isEnabled = isEnabled
    do {
      try githubAccountRepository.save(githubAccount)
      githubIssues.removeAll { !enabledGitHubRepositories.contains($0.repoFullName.lowercased()) }
      optimisticGitHubIssues.removeAll { !enabledGitHubRepositories.contains($0.issue.repoFullName.lowercased()) }
      githubRepositoryError = nil
      Task { await refresh() }
    } catch {
      githubRepositoryError = error.localizedDescription
    }
  }

  private var enabledGitHubRepositories: Set<String> {
    Set(githubAccount.repositories.filter(\.isEnabled).map { $0.fullName.lowercased() })
  }

  /// Persists a new refresh cadence selected from Settings.
  func setRefreshInterval(minutes: Int) {
    refreshIntervalMinutes = minutes
  }

  /// Persists how early the menu bar switches to the meeting title.
  func setMenuBarEventLeadTime(minutes: Int) {
    menuBarEventLeadTimeMinutes = minutes
    menuBarClockDate = Date()
  }

  /// Persists how long the menu bar title remains after the meeting starts.
  func setMenuBarEventPostStartGrace(minutes: Int) {
    menuBarEventPostStartGraceMinutes = minutes
    menuBarClockDate = Date()
  }

  /// Persists a new copy hotkey selected from Settings.
  func setCopyIssueHotkey(_ hotkey: String) {
    let normalized = Self.normalizedHotkey(hotkey, defaultValue: "c")
    guard !hoverHotkeys(excluding: copyIssueHotkey).contains(normalized) else { return }
    copyIssueHotkey = normalized
  }

  /// Persists a new status picker hotkey selected from Settings.
  func setStatusPickerHotkey(_ hotkey: String) {
    let normalized = Self.normalizedHotkey(hotkey, defaultValue: "s")
    guard !hoverHotkeys(excluding: statusPickerHotkey).contains(normalized) else { return }
    statusPickerHotkey = normalized
  }

  /// Persists a new priority picker hotkey selected from Settings.
  func setPriorityPickerHotkey(_ hotkey: String) {
    let normalized = Self.normalizedHotkey(hotkey, defaultValue: "p")
    guard !hoverHotkeys(excluding: priorityPickerHotkey).contains(normalized) else { return }
    priorityPickerHotkey = normalized
  }

  /// Persists a new due date picker hotkey selected from Settings.
  func setDueDatePickerHotkey(_ hotkey: String) {
    let normalized = Self.normalizedHotkey(hotkey, defaultValue: "d")
    guard !hoverHotkeys(excluding: dueDatePickerHotkey).contains(normalized) else { return }
    dueDatePickerHotkey = normalized
  }

  func setLabelPickerHotkey(_ hotkey: String) {
    let normalized = Self.normalizedHotkey(hotkey, defaultValue: "l")
    guard !hoverHotkeys(excluding: labelPickerHotkey).contains(normalized) else { return }
    labelPickerHotkey = normalized
  }

  func setAssigneePickerHotkey(_ hotkey: String) {
    let normalized = Self.normalizedHotkey(hotkey, defaultValue: "a")
    guard !hoverHotkeys(excluding: assigneePickerHotkey).contains(normalized) else { return }
    assigneePickerHotkey = normalized
  }

  private func hoverHotkeys(excluding value: String) -> [String] {
    [copyIssueHotkey, statusPickerHotkey, priorityPickerHotkey, dueDatePickerHotkey, labelPickerHotkey, assigneePickerHotkey]
      .filter { $0 != value }
  }

  /// Persists a new global shortcut for creating notes selected from Settings.
  @discardableResult
  func setNewNoteShortcut(_ shortcut: GlobalShortcut) -> Bool {
    guard registerGlobalShortcut(shortcut, for: .newNote) else { return false }
    newNoteShortcut = shortcut
    Self.persistShortcut(shortcut, forKey: Self.newNoteShortcutKey)
    return true
  }

  /// Persists a new global shortcut for creating Linear issues selected from Settings.
  @discardableResult
  func setNewLinearIssueShortcut(_ shortcut: GlobalShortcut) -> Bool {
    guard registerGlobalShortcut(shortcut, for: .newLinearIssue) else { return false }
    newLinearIssueShortcut = shortcut
    Self.persistShortcut(shortcut, forKey: Self.newLinearIssueShortcutKey)
    return true
  }

  /// Persists a new global shortcut for opening Google Calendar.
  @discardableResult
  func setOpenGoogleCalendarShortcut(_ shortcut: GlobalShortcut) -> Bool {
    guard registerGlobalShortcut(shortcut, for: .openGoogleCalendar) else { return false }
    openGoogleCalendarShortcut = shortcut
    Self.persistShortcut(shortcut, forKey: Self.openGoogleCalendarShortcutKey)
    return true
  }

  /// Persists a new global shortcut for creating GitHub issues selected from Settings.
  @discardableResult
  func setNewGitHubIssueShortcut(_ shortcut: GlobalShortcut) -> Bool {
    guard registerGlobalShortcut(shortcut, for: .newGitHubIssue) else { return false }
    newGitHubIssueShortcut = shortcut
    Self.persistShortcut(shortcut, forKey: Self.newGitHubIssueShortcutKey)
    return true
  }

  /// Opens Google Calendar's current week view without requesting write access.
  func openGoogleCalendar() {
    NSWorkspace.shared.open(URL(string: "https://calendar.google.com/calendar/u/0/r/week")!)
  }

  /// Persists whether calendar event rows show their source calendar names.
  func setShowsCalendarSourceNames(_ shows: Bool) {
    showsCalendarSourceNames = shows
  }

  /// Persists whether the calendar section appears in the menu bar popover.
  func setShowsCalendarSection(_ shows: Bool) {
    showsCalendarSection = shows
  }

  /// Persists whether the Linear section appears in the menu bar popover.
  func setShowsLinearSection(_ shows: Bool) {
    showsLinearSection = shows
  }

  /// Persists the issues tab selected in the menu.
  func setIssueSource(_ source: IssueSource) {
    guard issueSource != source else { return }
    issueSource = source
  }

  /// Persists whether the notes section appears in the menu bar popover.
  func setShowsNotesSection(_ shows: Bool) {
    showsNotesSection = shows
  }

  /// Persists whether the full-screen meeting alert is enabled.
  func setMeetingAlertEnabled(_ enabled: Bool) {
    meetingAlertEnabled = enabled
  }

  /// Persists how early the full-screen meeting alert may appear.
  func setMeetingAlertLead(minutes: Int) {
    meetingAlertLeadMinutes = minutes
  }

  /// Dismisses the full-screen meeting alert for the current event.
  func dismissMeetingAlert() {
    if let event = meetingAlertEvent {
      dismissedMeetingAlertEventIDs.insert(event.deduplicationKey ?? event.id)
    }
    meetingAlertEvent = nil
  }

  /// Opens the current alert event's meeting link and dismisses the alert.
  func joinMeetingAlert() {
    guard let event = meetingAlertEvent else { return }
    if let url = event.openURL ?? event.calendarURL {
      NSWorkspace.shared.open(url)
    }
    dismissMeetingAlert()
  }

  /// Persists a new Linear issue ordering and reapplies it immediately.
  func setLinearIssueOrder(_ order: LinearIssueOrder) {
    linearIssueOrder = order
  }

  /// Persists what the copy shortcut places on the clipboard.
  func setLinearCopyStyle(_ style: LinearCopyStyle) {
    linearCopyStyle = style
  }

  /// Persists the team preselected by the Linear issue creator.
  func setLinearIssueCreateDefaultTeamID(_ teamID: String) {
    linearIssueCreateDefaultTeamID = teamID
  }

  /// Persists the workflow state preselected by the Linear issue creator.
  func setLinearIssueCreateDefaultStateID(_ stateID: String) {
    linearIssueCreateDefaultStateID = stateID
  }

  /// Persists the priority preselected by the Linear issue creator.
  func setLinearIssueCreateDefaultPriority(_ priority: Int) {
    linearIssueCreateDefaultPriority = priority
  }

  /// Persists the project preselected by the Linear issue creator.
  func setLinearIssueCreateDefaultProjectID(_ projectID: String) {
    linearIssueCreateDefaultProjectID = projectID
  }

  /// Persists the label preselected by the Linear issue creator.
  func setLinearIssueCreateDefaultLabelID(_ labelID: String) {
    linearIssueCreateDefaultLabelID = labelID
  }

  /// Persists a new local note ordering and reapplies it immediately.
  func setLocalNoteSortOrder(_ order: LocalNoteSortOrder) {
    localNoteSortOrder = order
  }

  /// Persists how many local notes are shown before expansion.
  func setDefaultVisibleNoteCount(_ count: Int) {
    defaultVisibleNoteCount = count
  }

  /// Refreshes launch-at-login state from macOS.
  func refreshLaunchAtLoginStatus() {
    guard mockData == nil else {
      return
    }
    launchAtLoginEnabled = launchAtLoginService.isEnabled
  }

  /// Requests a launch-at-login change and mirrors the resulting macOS state.
  func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
    guard mockData == nil else {
      launchAtLoginEnabled = isEnabled
      return
    }
    do {
      try launchAtLoginService.setEnabled(isEnabled)
      launchAtLoginError = nil
      UserDefaults.standard.set(true, forKey: Self.launchAtLoginDefaultConfiguredKey)
      UserDefaults.standard.removeObject(forKey: Self.launchAtLoginDefaultPendingKey)
    } catch {
      launchAtLoginError = error.localizedDescription.compactLine(limit: 96)
    }
    refreshLaunchAtLoginStatus()
  }

  /// Whether additional fetched Linear issues can be shown without another refresh.
  var hasMoreIssues: Bool {
    visibleIssueCount < allIssues.count
  }

  /// Whether the issue list is showing rows beyond the initial page.
  var hasExpandedIssues: Bool {
    visibleIssueCount > Self.initialVisibleIssueCount
  }

  /// Label for the button that reveals more Linear issues.
  var showMoreIssuesLabel: String {
    let additionalCount = min(Self.issuePageSize, max(allIssues.count - visibleIssueCount, 0))
    return "Show \(additionalCount) more"
  }

  /// Reveals another page of already-fetched Linear issues.
  func showMoreIssues() {
    visibleIssueCount = min(visibleIssueCount + Self.issuePageSize, allIssues.count)
    applyLinearIssueOrder()
  }

  /// Collapses Linear issues back to the initial visible page.
  func showFewerIssues() {
    visibleIssueCount = Self.initialVisibleIssueCount
    applyLinearIssueOrder()
  }

  /// Whether additional fetched local notes can be shown without another refresh.
  var hasMoreNotes: Bool {
    visibleNoteCount < allNotes.count
  }

  /// Whether the note list is showing rows beyond the configured default.
  var hasExpandedNotes: Bool {
    visibleNoteCount > defaultVisibleNoteCount
  }

  /// Label for the button that reveals more local notes.
  var showMoreNotesLabel: String {
    let additionalCount = min(defaultVisibleNoteCount, max(allNotes.count - visibleNoteCount, 0))
    return "Show \(additionalCount) more"
  }

  /// Reveals another page of already-fetched local notes.
  func showMoreNotes() {
    visibleNoteCount = min(visibleNoteCount + defaultVisibleNoteCount, allNotes.count)
    applyLocalNoteSortOrder()
  }

  /// Collapses local notes back to the configured default.
  func showFewerNotes() {
    visibleNoteCount = defaultVisibleNoteCount
    applyLocalNoteSortOrder()
  }

  /// Toggles tomorrow's cached calendar events in the menu.
  func toggleTomorrowEvents() {
    isTomorrowExpanded.toggle()
  }

  /// Returns whether a keypress should copy the hovered Linear issue link.
  func matchesCopyIssueHotkey(_ characters: String) -> Bool {
    Self.hotkeyMatches(characters, configured: copyIssueHotkey)
  }

  /// Returns whether a keypress should open the status picker.
  func matchesStatusPickerHotkey(_ characters: String) -> Bool {
    Self.hotkeyMatches(characters, configured: statusPickerHotkey)
  }

  /// Returns whether a keypress should open the priority picker.
  func matchesPriorityPickerHotkey(_ characters: String) -> Bool {
    Self.hotkeyMatches(characters, configured: priorityPickerHotkey)
  }

  /// Returns whether a keypress should open the due date picker.
  func matchesDueDatePickerHotkey(_ characters: String) -> Bool {
    Self.hotkeyMatches(characters, configured: dueDatePickerHotkey)
  }

  func matchesLabelPickerHotkey(_ characters: String) -> Bool {
    Self.hotkeyMatches(characters, configured: labelPickerHotkey)
  }

  func matchesAssigneePickerHotkey(_ characters: String) -> Bool {
    Self.hotkeyMatches(characters, configured: assigneePickerHotkey)
  }

  /// Tracks which Linear issue is currently hovered for keyboard actions.
  func setHoveredIssue(_ target: IssueActionTarget?) {
    hoveredIssueTarget = target
  }

  /// Tracks which local note is currently hovered for row highlighting.
  func setHoveredNote(_ noteID: LocalNoteItem.ID?) {
    hoveredNoteID = noteID
  }

  /// Tracks which menu chrome control is currently hovered.
  func setHoveredControl(_ controlID: MenuControlID?) {
    hoveredControlID = controlID
  }

  /// Issue whose priority picker should currently be shown.
  var priorityPickerIssue: LinearIssueItem? {
    guard let priorityPickerIssueID else {
      return nil
    }
    return allIssues.first { $0.id == priorityPickerIssueID }
  }

  /// Opens the status picker for the hovered Linear issue.
  @discardableResult
  func presentStatusPickerForHoveredIssue() -> Bool {
    guard let target = validHoveredIssueTarget else { return false }
    statusPickerTarget = target
    priorityPickerIssueID = nil
    dueDatePickerIssueID = nil
    labelPickerTarget = nil
    assigneePickerTarget = nil
    return true
  }

  /// Opens the priority picker for the hovered Linear issue.
  @discardableResult
  func presentPriorityPickerForHoveredIssue() -> Bool {
    guard case .linear(let issueID)? = validHoveredIssueTarget else {
      return false
    }
    priorityPickerIssueID = issueID
    statusPickerTarget = nil
    dueDatePickerIssueID = nil
    labelPickerTarget = nil
    assigneePickerTarget = nil
    return true
  }

  /// Opens the due date picker for the hovered Linear issue.
  @discardableResult
  func presentDueDatePickerForHoveredIssue() -> Bool {
    guard case .linear(let issueID)? = validHoveredIssueTarget else {
      return false
    }
    dueDatePickerIssueID = issueID
    statusPickerTarget = nil
    priorityPickerIssueID = nil
    labelPickerTarget = nil
    assigneePickerTarget = nil
    return true
  }

  @discardableResult
  func presentLabelPickerForHoveredIssue() -> Bool {
    guard let target = validHoveredIssueTarget else { return false }
    labelPickerTarget = target
    dismissOtherPickers(kind: .label)
    return true
  }

  @discardableResult
  func presentAssigneePickerForHoveredIssue() -> Bool {
    guard let target = validHoveredIssueTarget else { return false }
    assigneePickerTarget = target
    dismissOtherPickers(kind: .assignee)
    return true
  }

  private var validHoveredIssueTarget: IssueActionTarget? {
    guard let target = hoveredIssueTarget else { return nil }
    switch target {
    case .linear(let id): return allIssues.contains { $0.id == id } ? target : nil
    case .github(let id): return githubIssues.contains { $0.id == id } ? target : nil
    }
  }

  private enum PickerKind { case label, assignee }
  private func dismissOtherPickers(kind: PickerKind) {
    statusPickerTarget = nil
    priorityPickerIssueID = nil
    dueDatePickerIssueID = nil
    if kind != .label { labelPickerTarget = nil }
    if kind != .assignee { assigneePickerTarget = nil }
  }

  /// Dismisses the status picker without changing Linear.
  func dismissStatusPicker() {
    statusPickerTarget = nil
  }

  /// Dismisses the priority picker without changing Linear.
  func dismissPriorityPicker() {
    priorityPickerIssueID = nil
  }

  /// Dismisses the due date picker without changing Linear.
  func dismissDueDatePicker() {
    dueDatePickerIssueID = nil
  }

  func dismissLabelPicker() { labelPickerTarget = nil }
  func dismissAssigneePicker() { assigneePickerTarget = nil }

  /// Tracks which calendar event is currently hovered for row highlighting.
  func setHoveredEvent(_ eventID: CalendarEventItem.ID?) {
    hoveredEventID = eventID
  }

  /// Copies the hovered issue link and briefly marks the row as copied.
  @discardableResult
  func copyHoveredIssueLink() -> Bool {
    guard let target = validHoveredIssueTarget else { return false }
    if case .github(let id) = target,
       let githubIssue = githubIssues.first(where: { $0.id == id }),
       let url = githubIssue.url {
      copyToClipboard(url.absoluteString, markingCopied: target)
      return true
    }
    guard case .linear(let id) = target,
          let issue = issues.first(where: { $0.id == id }) else {
      return false
    }

    let clipboardText: String?
    switch linearCopyStyle {
    case .link:
      clipboardText = issue.url?.absoluteString
    case .branchName:
      clipboardText = issue.branchName ?? issue.url?.absoluteString
    }

    guard let clipboardText else {
      return false
    }

    copyToClipboard(clipboardText, markingCopied: target)
    return true
  }

  /// Copies one string and flashes the copied indicator on the matching row.
  private func copyToClipboard(_ text: String, markingCopied target: IssueActionTarget) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copiedIssueTarget = target

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.4))
      if copiedIssueTarget == target {
        copiedIssueTarget = nil
      }
    }
  }

  /// Copies the hovered calendar event's meeting or event link and briefly marks the row.
  @discardableResult
  func copyHoveredEventLink() -> Bool {
    guard let hoveredEventID,
          let event = (events + tomorrowEvents).first(where: { $0.id == hoveredEventID }),
          let url = event.openURL ?? event.calendarURL else {
      return false
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
    copiedEventID = event.id

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.4))
      if copiedEventID == event.id {
        copiedEventID = nil
      }
    }

    return true
  }

  /// Changes a Linear issue status and updates the visible list.
  func changeIssueStatus(issueID: LinearIssueItem.ID, state: LinearWorkflowState) async {
    let target = IssueActionTarget.linear(issueID)
    guard updatingIssueTarget == nil else {
      return
    }

    updatingIssueTarget = target
    statusPickerTarget = nil

    if mockData != nil {
      if let issue = allIssues.first(where: { $0.id == issueID }) {
        replaceFetchedIssue(LinearIssueItem(
          id: issue.id,
          title: issue.title,
          priority: issue.priority,
          priorityLabel: issue.priorityLabel,
          stateName: state.name,
          stateID: state.id,
          stateType: state.type,
          workflowStates: issue.workflowStates,
          teamID: issue.teamID,
          labels: issue.labels,
          assignee: issue.assignee,
          dueDate: issue.dueDate,
          branchName: issue.branchName,
          url: issue.url
        ))
      }
      updatingIssueTarget = nil
      return
    }

    do {
      let updatedIssue = try await linearService.updateIssueStatus(issueID: issueID, stateID: state.id)
      replaceFetchedIssue(updatedIssue)
      linearError = nil
    } catch {
      linearError = error.localizedDescription
    }

    updatingIssueTarget = nil
  }

  /// Changes a Linear issue priority and updates the visible list.
  func changeIssuePriority(issueID: LinearIssueItem.ID, priority: LinearPriorityOption) async {
    guard updatingPriorityIssueID == nil else {
      return
    }

    updatingPriorityIssueID = issueID
    priorityPickerIssueID = nil

    if mockData != nil {
      if let issue = allIssues.first(where: { $0.id == issueID }) {
        replaceFetchedIssue(LinearIssueItem(
          id: issue.id,
          title: issue.title,
          priority: priority.value,
          priorityLabel: priority.label,
          stateName: issue.stateName,
          stateID: issue.stateID,
          stateType: issue.stateType,
          workflowStates: issue.workflowStates,
          teamID: issue.teamID,
          labels: issue.labels,
          assignee: issue.assignee,
          dueDate: issue.dueDate,
          branchName: issue.branchName,
          url: issue.url
        ))
      }
      updatingPriorityIssueID = nil
      return
    }

    do {
      let updatedIssue = try await linearService.updateIssuePriority(issueID: issueID, priority: priority.value)
      replaceFetchedIssue(updatedIssue)
      linearError = nil
    } catch {
      linearError = error.localizedDescription
    }

    updatingPriorityIssueID = nil
  }

  /// Changes or clears a Linear issue due date and updates the visible list.
  func changeIssueDueDate(issueID: LinearIssueItem.ID, dueDate: Date?) async {
    guard updatingDueDateIssueID == nil else {
      return
    }

    updatingDueDateIssueID = issueID
    dueDatePickerIssueID = nil

    let formattedDueDate = dueDate.flatMap { date in
      LinearIssueCreateDraft(dueDate: date).formattedDueDate
    }

    if mockData != nil {
      if let issue = allIssues.first(where: { $0.id == issueID }) {
        replaceFetchedIssue(LinearIssueItem(
          id: issue.id,
          title: issue.title,
          priority: issue.priority,
          priorityLabel: issue.priorityLabel,
          stateName: issue.stateName,
          stateID: issue.stateID,
          stateType: issue.stateType,
          workflowStates: issue.workflowStates,
          teamID: issue.teamID,
          labels: issue.labels,
          assignee: issue.assignee,
          dueDate: formattedDueDate,
          branchName: issue.branchName,
          url: issue.url
        ))
      }
      updatingDueDateIssueID = nil
      return
    }

    do {
      let updatedIssue = try await linearService.updateIssueDueDate(issueID: issueID, dueDate: formattedDueDate)
      replaceFetchedIssue(updatedIssue)
      linearError = nil
    } catch {
      linearError = error.localizedDescription
    }

    updatingDueDateIssueID = nil
  }

  /// Moves a Linear issue to its team's canceled workflow state.
  func cancelLinearIssue(issueID: LinearIssueItem.ID) async {
    guard updatingIssueTarget == nil else {
      return
    }

    guard let issue = allIssues.first(where: { $0.id == issueID }),
          let canceledState = issue.workflowStates.first(where: { $0.type == "canceled" }) else {
      linearError = "No canceled Linear state is available for this issue."
      return
    }

    await changeIssueStatus(issueID: issueID, state: canceledState)
  }

  /// Closes or reopens a GitHub issue. Closed issues leave the assigned-open list immediately.
  func changeGitHubIssueState(issueID: String, isOpen: Bool) async {
    let target = IssueActionTarget.github(issueID)
    guard updatingIssueTarget == nil,
          let issue = githubIssues.first(where: { $0.id == issueID }) else { return }
    updatingIssueTarget = target
    statusPickerTarget = nil
    defer { updatingIssueTarget = nil }
    if mockData == nil {
      do {
        try await githubService.updateIssueState(repoFullName: issue.repoFullName, number: issue.number, isOpen: isOpen)
      } catch {
        githubError = error.localizedDescription
        return
      }
    }
    if !isOpen {
      githubIssues.removeAll { $0.id == issueID }
      optimisticGitHubIssues.removeAll { $0.issue.id == issueID }
    }
    githubError = nil
  }

  /// Loads labels appropriate for one issue target.
  func labelOptions(for target: IssueActionTarget) async throws -> [IssueLabelOption] {
    switch target {
    case .linear(let id):
      guard let issue = allIssues.first(where: { $0.id == id }) else { return [] }
      return try await linearIssueCreateLabelOptions(teamID: issue.teamID).map {
        IssueLabelOption(id: $0.id, name: $0.name, color: $0.color)
      }
    case .github(let id):
      guard let issue = githubIssues.first(where: { $0.id == id }) else { return [] }
      if let mockData { return mockData.labels.map { IssueLabelOption(id: $0.id, name: $0.name, color: $0.color) } }
      return try await githubService.fetchLabels(repoFullName: issue.repoFullName).map {
        IssueLabelOption(id: $0.id, name: $0.name, color: $0.color)
      }
    }
  }

  func selectedLabelIDs(for target: IssueActionTarget) -> Set<String> {
    switch target {
    case .linear(let id): return Set(allIssues.first { $0.id == id }?.labels.map(\.id) ?? [])
    case .github(let id): return Set(githubIssues.first { $0.id == id }?.labels.map(\.id) ?? [])
    }
  }

  /// Toggles one label while preserving every other applied label.
  func toggleLabel(target: IssueActionTarget, option: IssueLabelOption) async {
    guard updatingIssueTarget == nil else { return }
    updatingIssueTarget = target
    defer { updatingIssueTarget = nil }
    switch target {
    case .linear(let id):
      guard let issue = allIssues.first(where: { $0.id == id }) else { return }
      var ids = issue.labels.map(\.id)
      if let index = ids.firstIndex(of: option.id) { ids.remove(at: index) } else { ids.append(option.id) }
      do {
        if mockData != nil {
          replaceFetchedIssue(issue.replacing(labels: ids.map { labelID in
            let existing = issue.labels.first { $0.id == labelID }
            return existing ?? LinearLabelOption(id: option.id, name: option.name, color: option.color)
          }))
        } else {
          replaceFetchedIssue(try await linearService.updateIssueLabels(issueID: id, labelIDs: ids))
        }
        linearError = nil
      } catch { linearError = error.localizedDescription }
    case .github(let id):
      guard let issue = githubIssues.first(where: { $0.id == id }) else { return }
      var labels = issue.labels
      if let index = labels.firstIndex(where: { $0.id == option.id }) {
        labels.remove(at: index)
      } else {
        labels.append(GitHubLabelOption(name: option.name, color: option.color))
      }
      do {
        if mockData == nil {
          try await githubService.updateIssueLabels(repoFullName: issue.repoFullName, number: issue.number, labels: labels.map(\.name))
        }
        replaceGitHubIssue(issue.replacing(labels: labels))
        githubError = nil
      } catch { githubError = error.localizedDescription }
    }
  }

  /// Loads assignable users appropriate for one issue target.
  func assigneeOptions(for target: IssueActionTarget) async throws -> [IssueAssigneeOption] {
    switch target {
    case .linear:
      return [IssueAssigneeOption(id: "", name: "Unassigned")] + (try await linearIssueCreateAssigneeOptions().map {
        IssueAssigneeOption(id: $0.id, name: $0.label)
      })
    case .github(let id):
      guard let issue = githubIssues.first(where: { $0.id == id }) else { return [] }
      if let mockData { return mockData.users.map { IssueAssigneeOption(id: $0.id, name: $0.label) } }
      return try await githubService.fetchAssignees(repoFullName: issue.repoFullName).map {
        IssueAssigneeOption(id: $0.id, name: $0.login)
      }
    }
  }

  func selectedAssigneeIDs(for target: IssueActionTarget) -> Set<String> {
    switch target {
    case .linear(let id): return Set(allIssues.first { $0.id == id }?.assignee.map { [$0.id] } ?? [""])
    case .github(let id): return Set(githubIssues.first { $0.id == id }?.assignees.map(\.id) ?? [])
    }
  }

  /// Applies singular Linear assignment or toggles one GitHub assignee while preserving the rest.
  func toggleAssignee(target: IssueActionTarget, option: IssueAssigneeOption) async {
    guard updatingIssueTarget == nil else { return }
    updatingIssueTarget = target
    defer { updatingIssueTarget = nil }
    switch target {
    case .linear(let id):
      guard let issue = allIssues.first(where: { $0.id == id }) else { return }
      let assigneeID = option.id.isEmpty || issue.assignee?.id == option.id ? nil : option.id
      do {
        if mockData != nil {
          if linearIssueFilter == .allOpen {
            let newAssignee: LinearUserOption? = assigneeID.map {
              LinearUserOption(id: $0, name: option.name, displayName: option.name, isActive: true)
            }
            replaceFetchedIssue(issue.replacing(assignee: .some(newAssignee)))
          } else {
            allIssues.removeAll { $0.id == id }
            applyLinearIssueOrder()
          }
        } else {
          let updatedIssue = try await linearService.updateIssueAssignee(issueID: id, assigneeID: assigneeID)
          if linearIssueFilter == .allOpen {
            replaceFetchedIssue(updatedIssue)
          } else {
            // The menu only shows issues assigned to the viewer, so any singular
            // reassignment or unassignment removes this issue from the active list.
            allIssues.removeAll { $0.id == id }
            applyLinearIssueOrder()
          }
        }
        linearError = nil
      } catch { linearError = error.localizedDescription }
    case .github(let id):
      guard let issue = githubIssues.first(where: { $0.id == id }) else { return }
      var assignees = issue.assignees
      if let index = assignees.firstIndex(where: { $0.id == option.id }) {
        assignees.remove(at: index)
      } else {
        assignees.append(GitHubAssigneeOption(login: option.name))
      }
      do {
        if mockData == nil {
          try await githubService.updateIssueAssignees(repoFullName: issue.repoFullName, number: issue.number, assignees: assignees.map(\.login))
        }
        let viewerLogin = connectionStatuses
          .first(where: { $0.provider == .github })?
          .accountLabel?
          .lowercased()
        if githubIssueFilter == .allOpen {
          replaceGitHubIssue(issue.replacing(assignees: assignees))
        } else if let viewerLogin, !assignees.contains(where: { $0.login.lowercased() == viewerLogin }) {
          githubIssues.removeAll { $0.id == id }
          optimisticGitHubIssues.removeAll { $0.issue.id == id }
        } else {
          replaceGitHubIssue(issue.replacing(assignees: assignees))
        }
        githubError = nil
      } catch { githubError = error.localizedDescription }
    }
  }

  /// Loads Linear teams and states for the issue creator.
  func linearIssueCreateTeamOptions() async throws -> [LinearTeamOption] {
    if let mockData { return mockData.teams }
    return try await linearService.fetchTeamOptions()
  }

  /// Loads Linear users for the issue creator assignee picker.
  func linearIssueCreateAssigneeOptions() async throws -> [LinearUserOption] {
    if let mockData { return mockData.users }
    return try await linearService.fetchUserOptions()
  }

  /// Loads Linear projects for the issue creator project picker.
  func linearIssueCreateProjectOptions() async throws -> [LinearProjectOption] {
    if let mockData { return mockData.projects }
    return try await linearService.fetchProjectOptions()
  }

  /// Loads a team's cycles for the issue creator cycle picker.
  func linearIssueCreateCycleOptions(teamID: String) async throws -> [LinearCycleOption] {
    if let mockData { return mockData.cycles }
    return try await linearService.fetchCycleOptions(teamID: teamID)
  }

  /// Loads a team's labels for the issue creator label picker.
  func linearIssueCreateLabelOptions(teamID: String) async throws -> [LinearLabelOption] {
    if let mockData { return mockData.labels }
    return try await linearService.fetchLabelOptions(teamID: teamID)
  }

  /// Loads a project's milestones for the issue creator milestone picker.
  func linearIssueCreateMilestoneOptions(projectID: String) async throws -> [LinearMilestoneOption] {
    if let mockData { return mockData.milestones }
    return try await linearService.fetchMilestoneOptions(projectID: projectID)
  }

  /// Creates a Linear issue from a draft and refreshes assigned issues.
  func createLinearIssue(draft: LinearIssueCreateDraft) async throws {
    if let mockData {
      let team = mockData.teams.first { $0.id == draft.team }
      let state = team?.states.first(where: { $0.id == draft.state })
        ?? team?.states.first(where: { $0.type == "unstarted" })
      let priority = LinearPriorityOption.allCases.first(where: { $0.value == draft.priority })
        ?? LinearPriorityOption(value: 0, label: "No priority")
      allIssues.append(LinearIssueItem(
        id: "DAY-\(120 + allIssues.count)",
        title: draft.title,
        priority: priority.value,
        priorityLabel: priority.label,
        stateName: state?.name ?? "Todo",
        stateID: state?.id ?? "mock-todo",
        stateType: state?.type ?? "unstarted",
        workflowStates: team?.states ?? [],
        teamID: team?.id ?? "mock-team",
        labels: draft.label.isEmpty ? [] : mockData.labels.filter { $0.id == draft.label },
        assignee: nil,
        dueDate: draft.formattedDueDate,
        branchName: nil,
        url: URL(string: "https://linear.app/dayline")
      ))
      applyLinearIssueOrder()
      lastUpdatedAt = Date()
      return
    }

    try await linearService.createIssue(draft: draft)
    lastUpdatedAt = Date()
    Task { await refresh() }
  }

  /// Loads a repository's assignable collaborators for the GitHub issue creator.
  func githubIssueCreateAssigneeOptions(repoFullName: String) async throws -> [GitHubAssigneeOption] {
    if let mockData {
      var logins = Set(mockData.githubIssues.flatMap { $0.assignees.map(\.login) })
      if let own = connectionStatuses.first(where: { $0.provider == .github })?.accountLabel {
        logins.insert(own)
      }
      return logins.sorted().map { GitHubAssigneeOption(login: $0) }
    }
    return try await githubService.fetchAssignees(repoFullName: repoFullName)
  }

  /// Loads a repository's labels for the GitHub issue creator.
  func githubIssueCreateLabelOptions(repoFullName: String) async throws -> [GitHubLabelOption] {
    if let mockData {
      return mockData.githubIssues
        .flatMap(\.labels)
        .reduce(into: [String: GitHubLabelOption]()) { $0[$1.name] = $1 }
        .values
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    return try await githubService.fetchLabels(repoFullName: repoFullName)
  }

  /// Creates a GitHub issue in a repository, shows it optimistically, and refreshes assigned issues.
  func createGitHubIssue(repoFullName: String, title: String, body: String, labels: [String], assignees: [String]) async throws {
    if let mockData {
      let knownLabels = mockData.githubIssues.flatMap(\.labels)
      githubIssues.insert(GitHubIssueItem(
        id: "mock-github-\(UUID().uuidString)",
        title: title,
        repoFullName: repoFullName,
        number: (githubIssues.map(\.number).max() ?? 100) + 1,
        url: URL(string: "https://github.com/\(repoFullName)"),
        updatedAt: Date(),
        labels: labels.map { name in
          knownLabels.first(where: { $0.name == name }) ?? GitHubLabelOption(name: name, color: "cccccc")
        },
        assignees: assignees.map { GitHubAssigneeOption(login: $0) }
      ), at: 0)
      lastUpdatedAt = Date()
      return
    }

    let created = try await githubService.createIssue(
      repoFullName: repoFullName,
      title: title,
      body: body,
      labels: labels,
      assignees: assignees
    )
    insertOptimisticGitHubIssue(created)
    lastUpdatedAt = Date()
    Task { await refresh() }
  }

  /// Shows a freshly created issue until GitHub's search-backed feeds include it.
  private func insertOptimisticGitHubIssue(_ issue: GitHubIssueItem) {
    guard matchesCurrentGitHubFilter(issue) else { return }
    optimisticGitHubIssues.removeAll { $0.issue.id == issue.id }
    optimisticGitHubIssues.append((issue: issue, insertedAt: Date()))
    githubIssues.removeAll { $0.id == issue.id }
    githubIssues.insert(issue, at: 0)
  }

  /// Whether an issue belongs in the feed selected by the current GitHub filter.
  private func matchesCurrentGitHubFilter(_ issue: GitHubIssueItem) -> Bool {
    switch githubIssueFilter {
    case .allOpen:
      return true
    case .assignedToMe:
      let ownLogin = connectionStatuses.first(where: { $0.provider == .github })?.accountLabel?.lowercased()
      return ownLogin != nil && issue.assignees.contains { $0.login.lowercased() == ownLogin }
    }
  }

  /// Reconciles optimistic issues with a fetched feed, expiring entries GitHub still has not indexed.
  private func mergingOptimisticGitHubIssues(into fetched: [GitHubIssueItem]) -> [GitHubIssueItem] {
    let cutoff = Date().addingTimeInterval(-90)
    let enabledRepositories = enabledGitHubRepositories
    optimisticGitHubIssues.removeAll { $0.insertedAt < cutoff }
    optimisticGitHubIssues.removeAll { !enabledRepositories.contains($0.issue.repoFullName.lowercased()) }
    let fetchedIDs = Set(fetched.map(\.id))
    optimisticGitHubIssues.removeAll { fetchedIDs.contains($0.issue.id) }
    let missing = optimisticGitHubIssues.map(\.issue)
      .filter { !fetchedIDs.contains($0.id) && matchesCurrentGitHubFilter($0) }
    return missing + fetched
  }

  /// Returns a local note by identifier.
  func localNote(withID noteID: LocalNoteItem.ID) -> LocalNoteItem? {
    allNotes.first { $0.id == noteID }
  }

  /// Creates or updates a local note and persists the full collection.
  @discardableResult
  func saveLocalNote(id noteID: LocalNoteItem.ID?, text: String) throws -> LocalNoteItem {
    let previousNotes = allNotes
    let now = Date()

    let savedNote: LocalNoteItem
    if let noteID, let index = allNotes.firstIndex(where: { $0.id == noteID }) {
      allNotes[index].text = text
      allNotes[index].updatedAt = now
      savedNote = allNotes[index]
    } else if noteID != nil {
      notesError = StatusStoreError.missingLocalNote.localizedDescription
      throw StatusStoreError.missingLocalNote
    } else {
      savedNote = LocalNoteItem(
        id: UUID().uuidString,
        text: text,
        createdAt: now,
        updatedAt: now
      )
      allNotes.append(savedNote)
    }

    do {
      if mockData == nil {
        try notesService.saveNotes(allNotes)
      }
      applyLocalNoteSortOrder()
      notesError = nil
      return savedNote
    } catch {
      allNotes = previousNotes
      applyLocalNoteSortOrder()
      notesError = error.localizedDescription
      throw error
    }
  }

  /// Deletes a local note and persists the updated collection.
  func deleteLocalNote(id noteID: LocalNoteItem.ID) {
    let previousNotes = allNotes
    allNotes.removeAll { $0.id == noteID }

    do {
      if mockData == nil {
        try notesService.saveNotes(allNotes)
      }
      visibleNoteCount = min(max(defaultVisibleNoteCount, visibleNoteCount), max(defaultVisibleNoteCount, allNotes.count))
      applyLocalNoteSortOrder()
      notesError = nil
    } catch {
      allNotes = previousNotes
      applyLocalNoteSortOrder()
      notesError = error.localizedDescription
    }
  }

  /// Schedules the repeating refresh timer using the current cadence.
  private func scheduleRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshIntervalMinutes * 60), repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.refresh()
      }
    }
    refreshTimer?.tolerance = min(TimeInterval(refreshIntervalMinutes * 6), 60)
  }

  /// Schedules a lightweight clock used only for menu bar countdown text.
  private func scheduleMenuBarClockTimer() {
    menuBarClockTimer?.invalidate()
    menuBarClockTimer = Timer.scheduledTimer(withTimeInterval: Self.menuBarClockRefreshSeconds, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.menuBarClockDate = Date()
      }
    }
    menuBarClockTimer?.tolerance = 2
  }

  /// Runs a Google authorization and assigns its tokens only after identity verification.
  private func authorizeGoogleAccount(reconnecting expectedAccount: GoogleAccount?) async {
    guard mockData == nil, !isGoogleAuthorizationInProgress else { return }

    isGoogleAuthorizationInProgress = true
    googleAuthorizationError = nil
    connectionRevisions[.google, default: 0] += 1

    if let expectedAccount {
      updateGoogleAccountStatus(
        expectedAccount.id,
        state: .connecting,
        detail: "Finish sign-in in your browser."
      )
    } else {
      updateConnectionStatus(
        .google,
        state: .connecting,
        detail: "Finish sign-in in your browser.",
        accountLabel: nil
      )
    }

    var pendingSession: OAuthSession?

    do {
      let pendingID = UUID()
      let session = OAuthSession(
        provider: .google,
        credentials: googleAccountRepository.credentials,
        credentialAccount: "google.pending.\(pendingID.uuidString.lowercased())"
      )
      pendingSession = session
      let tokens = try await session.authorize()
      await session.stage(tokens)
      let discovery = try await CalendarService(authSession: session).fetchAccountDiscovery()

      if let expectedID = expectedAccount?.providerAccountID,
         expectedID.caseInsensitiveCompare(discovery.providerAccountID) != .orderedSame {
        let selectedAccountIsAlreadyLinked = googleAccounts.contains {
          $0.account.providerAccountID?.caseInsensitiveCompare(discovery.providerAccountID) == .orderedSame
        }
        if !selectedAccountIsAlreadyLinked {
          await session.signOut()
        }
        throw StatusStoreError.googleAccountMismatch(
          expected: expectedAccount?.label ?? expectedID,
          actual: discovery.displayLabel
        )
      }

      let existingIndex = googleAccounts.firstIndex {
        $0.account.providerAccountID?.caseInsensitiveCompare(discovery.providerAccountID) == .orderedSame
      }
      let targetIndex: Int?
      let targetAccount: GoogleAccount

      if let expectedAccount,
         let reconnectIndex = googleAccounts.firstIndex(where: { $0.id == expectedAccount.id }) {
        targetIndex = reconnectIndex
        targetAccount = googleAccounts[reconnectIndex].account
      } else if let existingIndex {
        targetIndex = existingIndex
        targetAccount = googleAccounts[existingIndex].account
      } else {
        targetIndex = nil
        targetAccount = GoogleAccount(
          id: UUID(),
          providerAccountID: nil,
          displayLabel: nil,
          calendars: []
        )
      }

      let targetSession = googleSession(for: targetAccount)
      guard let verifiedTokens = try await session.currentTokens() else {
        throw OAuthError.notSignedIn
      }
      try await targetSession.install(verifiedTokens)
      await session.discardCredentials()
      pendingSession = nil

      var verifiedAccount = targetAccount.reconcilingCalendars(discovery.calendars)
      verifiedAccount.providerAccountID = discovery.providerAccountID
      verifiedAccount.displayLabel = discovery.displayLabel
      let verifiedStatus = GoogleAccountStatus(account: verifiedAccount, state: .connected, detail: nil)
      if let targetIndex {
        googleAccounts[targetIndex] = verifiedStatus
      } else {
        googleAccounts.append(verifiedStatus)
      }

      connectionRevisions[.google, default: 0] += 1
      persistGoogleAccounts()
      updateGoogleAggregateStatus()
      undismissProvider(.google)
      isGoogleAuthorizationInProgress = false
      await refresh()
      presentSettingsAfterAuth()
    } catch OAuthError.authorizationCancelled {
      await pendingSession?.discardCredentials()
      isGoogleAuthorizationInProgress = false
      if let expectedAccount {
        updateGoogleAccountStatus(expectedAccount.id, state: .disconnected, detail: "Reconnect required.")
        connectionRevisions[.google, default: 0] += 1
      }
      updateGoogleAggregateStatus()
    } catch {
      await pendingSession?.discardCredentials()
      isGoogleAuthorizationInProgress = false
      googleAuthorizationError = error.localizedDescription.compactLine(limit: 120)
      if let expectedAccount {
        updateGoogleAccountStatus(
          expectedAccount.id,
          state: .disconnected,
          detail: googleAuthorizationError
        )
        connectionRevisions[.google, default: 0] += 1
      }
      updateGoogleAggregateStatus()
    }
  }

  /// Returns the cached account-scoped session or creates it on demand.
  private func googleSession(for account: GoogleAccount) -> OAuthSession {
    if let session = googleSessions[account.id] {
      return session
    }
    let session = OAuthSession(
      provider: .google,
      credentials: googleAccountRepository.credentials,
      credentialAccount: account.credentialAccount
    )
    googleSessions[account.id] = session
    return session
  }

  /// Persists the current Google account descriptors without runtime state.
  private func persistGoogleAccounts() {
    do {
      try googleAccountRepository.save(googleAccounts.map(\.account))
    } catch {
      googleAuthorizationError = error.localizedDescription
    }
  }

  /// Recomputes the provider-level Google status retained for first-run setup.
  private func updateGoogleAggregateStatus() {
    if googleAccounts.isEmpty {
      let detail = AuthProvider.google.isConfigured
        ? googleAuthorizationError
        : "This build is missing its OAuth client ID."
      updateConnectionStatus(.google, state: .disconnected, detail: detail, accountLabel: nil)
      return
    }

    let connectedCount = googleAccounts.filter(\.isConnected).count
    if connectedCount > 0 {
      let label = connectedCount == 1
        ? googleAccounts.first(where: \.isConnected)?.account.label
        : "\(connectedCount) accounts"
      updateConnectionStatus(.google, state: .connected, detail: nil, accountLabel: label)
    } else if isGoogleAuthorizationInProgress {
      updateConnectionStatus(
        .google,
        state: .connecting,
        detail: "Finish sign-in in your browser.",
        accountLabel: nil
      )
    } else {
      updateConnectionStatus(.google, state: .disconnected, detail: "Reconnect required.", accountLabel: nil)
    }
  }

  /// Updates one Google account's runtime status in place.
  private func updateGoogleAccountStatus(_ accountID: UUID, state: ConnectionState, detail: String?) {
    guard let index = googleAccounts.firstIndex(where: { $0.id == accountID }) else { return }
    googleAccounts[index].state = state
    googleAccounts[index].detail = detail
  }

  /// Whether at least one Google account can currently contribute calendar events.
  private var hasConnectedGoogleAccount: Bool {
    googleAccounts.contains(where: \.isConnected)
  }

  /// Returns whether one provider currently has usable credentials.
  private func isConnected(_ provider: AuthProvider) -> Bool {
    connectionStatuses.first { $0.provider == provider }?.isConnected == true
  }

  /// Replaces one provider's connection status in the published list.
  private func updateConnectionStatus(
    _ provider: AuthProvider,
    state: ConnectionState,
    detail: String?,
    accountLabel: String?
  ) {
    guard let index = connectionStatuses.firstIndex(where: { $0.provider == provider }) else {
      return
    }
    connectionStatuses[index].state = state
    connectionStatuses[index].detail = detail
    connectionStatuses[index].accountLabel = accountLabel
  }

  /// Marks a provider as needing sign-in again when its tokens are rejected.
  private func handleFetchFailure(_ error: Error, for provider: AuthProvider) {
    guard let oauthError = error as? OAuthError else {
      return
    }
    switch oauthError {
    case .reauthenticationRequired, .notSignedIn:
      break
    default:
      return
    }
    connectionRevisions[provider, default: 0] += 1
    if provider == .github {
      Task { await githubAuth.signOut() }
    }
    updateConnectionStatus(provider, state: .disconnected, detail: "Sign in again.", accountLabel: nil)
  }

  /// Loads a display label for the connected provider account.
  private func fetchAccountLabel(for provider: AuthProvider) async throws -> String {
    switch provider {
    case .google:
      googleAccounts.first?.account.label ?? "Google Calendar"
    case .linear:
      try await linearService.fetchAccountLabel()
    case .github:
      try await githubService.fetchAccountLabel()
    }
  }

  /// Opens Settings after a successful browser auth so the user can confirm the account.
  private func presentSettingsAfterAuth() {
    settingsPresentationRequestID = UUID()
  }

  /// Starts the global hotkey handler and registers the configured shortcuts.
  private func startGlobalHotkeys() {
    globalHotkeyService.start { [weak self] hotkey in
      guard let self else {
        return
      }
      switch hotkey {
      case .newNote:
        self.noteCreationRequestID = UUID()
      case .newLinearIssue:
        guard self.availableIssueSources.contains(.linear) else { return }
        self.linearIssueCreationRequestID = UUID()
      case .newGitHubIssue:
        guard self.availableIssueSources.contains(.github) else { return }
        self.githubIssueCreationRequestID = UUID()
      case .openGoogleCalendar:
        self.openGoogleCalendar()
      }
    }
    registerPersistedGlobalShortcuts()
  }

  /// Registers the persisted global shortcuts at launch.
  private func registerPersistedGlobalShortcuts() {
    let noteStatus = globalHotkeyService.update(shortcut: newNoteShortcut, for: .newNote)
    let linearStatus = globalHotkeyService.update(shortcut: newLinearIssueShortcut, for: .newLinearIssue)
    let calendarStatus = globalHotkeyService.update(shortcut: openGoogleCalendarShortcut, for: .openGoogleCalendar)
    let githubStatus = globalHotkeyService.update(shortcut: newGitHubIssueShortcut, for: .newGitHubIssue)
    if noteStatus != noErr {
      globalShortcutError = Self.globalShortcutRegistrationError(newNoteShortcut, status: noteStatus)
    } else if linearStatus != noErr {
      globalShortcutError = Self.globalShortcutRegistrationError(newLinearIssueShortcut, status: linearStatus)
    } else if calendarStatus != noErr {
      globalShortcutError = Self.globalShortcutRegistrationError(openGoogleCalendarShortcut, status: calendarStatus)
    } else if githubStatus != noErr {
      globalShortcutError = Self.globalShortcutRegistrationError(newGitHubIssueShortcut, status: githubStatus)
    }
  }

  /// Attempts one global shortcut replacement without discarding the previous registration.
  private func registerGlobalShortcut(_ shortcut: GlobalShortcut, for hotkey: GlobalHotkeyService.Hotkey) -> Bool {
    let status = globalHotkeyService.update(shortcut: shortcut, for: hotkey)
    guard status == noErr else {
      globalShortcutError = Self.globalShortcutRegistrationError(shortcut, status: status)
      return false
    }
    globalShortcutError = nil
    return true
  }

  /// User-facing registration failure that identifies the rejected shortcut.
  private static func globalShortcutRegistrationError(_ shortcut: GlobalShortcut, status: OSStatus) -> String {
    "Could not register \(shortcut.displayString). macOS or another app may already be using it. (\(status))"
  }

  /// Loads a persisted global shortcut, falling back to the default when absent or invalid.
  private static func loadShortcut(forKey key: String, defaultValue: GlobalShortcut) -> GlobalShortcut {
    guard let data = UserDefaults.standard.data(forKey: key),
          let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) else {
      return defaultValue
    }
    return shortcut
  }

  /// Persists a global shortcut as JSON data.
  private static func persistShortcut(_ shortcut: GlobalShortcut, forKey key: String) {
    guard let data = try? JSONEncoder().encode(shortcut) else {
      return
    }
    UserDefaults.standard.set(data, forKey: key)
  }

  /// Returns the event that should currently replace the menu bar icon.
  private func menuBarEvent(at now: Date) -> CalendarEventItem? {
    let leadTime = TimeInterval(menuBarEventLeadTimeMinutes * 60)
    let postStartGrace = TimeInterval(menuBarEventPostStartGraceMinutes * 60)

    return CalendarEventItem.menuBarCandidate(
      in: events,
      at: now,
      leadTime: leadTime,
      postStartGrace: postStartGrace
    )
  }

  /// Recomputes which event, if any, the full-screen meeting alert should present.
  private func updateMeetingAlert() {
    guard meetingAlertEnabled else {
      meetingAlertEvent = nil
      return
    }

    let now = menuBarClockDate
    let lead = TimeInterval(meetingAlertLeadMinutes * 60)
    // Evaluate against the uncapped merged source pool so capped menu slices
    // cannot hide meetings still inside the alert lead window.
    meetingAlertEvent = CalendarEventItem.mergedAgenda(googleSourceEvents)
      .filter { event in
        // Skip all-day style events that would fire the alert at midnight.
        guard event.endDate.timeIntervalSince(event.startDate) < 24 * 60 * 60 else { return false }
        return now >= event.startDate.addingTimeInterval(-lead)
          && now < min(event.endDate, event.startDate.addingTimeInterval(Self.meetingAlertPostStartGrace))
          && !dismissedMeetingAlertEventIDs.contains(event.deduplicationKey ?? event.id)
      }
      .min { $0.startDate < $1.startDate }
  }

  /// Applies the selected Linear ordering to fetched issue candidates.
  private func applyLinearIssueOrder() {
    issues = sortedLinearIssues(allIssues)
      .prefix(visibleIssueCount)
      .map { $0 }
  }

  /// Applies the selected local ordering to fetched note candidates.
  private func applyLocalNoteSortOrder() {
    notes = sortedLocalNotes(allNotes)
      .prefix(visibleNoteCount)
      .map { $0 }
  }

  /// Replaces or removes an updated issue, matching the active issue filter.
  private func replaceFetchedIssue(_ updatedIssue: LinearIssueItem) {
    allIssues.removeAll { $0.id == updatedIssue.id }

    if updatedIssue.stateType != "completed" && updatedIssue.stateType != "canceled" {
      allIssues.append(updatedIssue)
    }

    applyLinearIssueOrder()
  }

  private func replaceGitHubIssue(_ updatedIssue: GitHubIssueItem) {
    guard let index = githubIssues.firstIndex(where: { $0.id == updatedIssue.id }) else { return }
    githubIssues[index] = updatedIssue
    if let optimisticIndex = optimisticGitHubIssues.firstIndex(where: { $0.issue.id == updatedIssue.id }) {
      optimisticGitHubIssues[optimisticIndex].issue = updatedIssue
    }
  }

  /// Returns Linear issues sorted by the current user preference.
  private func sortedLinearIssues(_ issues: [LinearIssueItem]) -> [LinearIssueItem] {
    issues.sorted { lhs, rhs in
      switch linearIssueOrder {
      case .priority:
        comparePriority(lhs, rhs) ?? compareStatus(lhs, rhs) ?? compareDueDate(lhs, rhs) ?? compareID(lhs, rhs)
      case .dueDate:
        compareDueDate(lhs, rhs) ?? comparePriority(lhs, rhs) ?? compareID(lhs, rhs)
      case .status:
        compareStatus(lhs, rhs) ?? comparePriority(lhs, rhs) ?? compareDueDate(lhs, rhs) ?? compareID(lhs, rhs)
      case .title:
        compareTitle(lhs, rhs) ?? comparePriority(lhs, rhs) ?? compareID(lhs, rhs)
      }
    }
  }

  /// Returns local notes sorted by the current user preference.
  private func sortedLocalNotes(_ notes: [LocalNoteItem]) -> [LocalNoteItem] {
    notes.sorted { lhs, rhs in
      switch localNoteSortOrder {
      case .updatedAt:
        compareNewest(lhs.updatedAt, rhs.updatedAt) ?? compareNoteTitle(lhs, rhs) ?? compareNoteID(lhs, rhs)
      case .createdAt:
        compareNewest(lhs.createdAt, rhs.createdAt) ?? compareNoteTitle(lhs, rhs) ?? compareNoteID(lhs, rhs)
      case .title:
        compareNoteTitle(lhs, rhs) ?? compareNewest(lhs.updatedAt, rhs.updatedAt) ?? compareNoteID(lhs, rhs)
      }
    }
  }

  /// Loads local notes from disk into the in-memory sorted list.
  private func loadPersistedNotes() {
    do {
      allNotes = try notesService.loadNotes()
      applyLocalNoteSortOrder()
      notesError = nil
    } catch {
      allNotes = []
      applyLocalNoteSortOrder()
      notesError = error.localizedDescription
    }
  }

  /// Restores the isolated screenshot state without touching OAuth or disk persistence.
  private func applyMockData(_ mockData: MockData) {
    if ProcessInfo.processInfo.arguments.contains("--mock-meeting-alert") {
      let now = Date()
      let alertEvent = CalendarEventItem(
        id: "mock-meeting-alert",
        title: "Product stand-up",
        startDate: now,
        endDate: now.addingTimeInterval(30 * 60),
        location: nil,
        calendarURL: URL(string: "https://calendar.google.com"),
        openURL: URL(string: "https://meet.google.com/mock-dayline-demo"),
        sourceCalendarNames: ["Product Team"]
      )
      events = [alertEvent] + mockData.events
      meetingAlertEvent = alertEvent
    } else {
      events = mockData.events
    }
    googleSourceEvents = events
    tomorrowEvents = mockData.tomorrowEvents
    allIssues = mockData.issues
    allNotes = mockData.notes
    linearAccount = LinearAccount(
      workspaceName: "Dayline",
      userLabel: "Alex Morgan",
      teams: mockData.teams.map {
        LinearTeamSelection(id: $0.id, key: $0.key, name: $0.name, isEnabled: true)
      },
      hasDiscoveredTeams: true
    )
    githubIssues = mockData.githubIssues
    githubAccount = GitHubAccount(repositories: Array(Set(mockData.githubIssues.map(\.repoFullName))).map {
      GitHubRepository(fullName: $0, isEnabled: true)
    }.sorted { $0.fullName < $1.fullName })
    connectionStatuses = mockData.connectionStatuses
    googleAccounts = mockData.googleAccounts
    visibleIssueCount = Self.initialVisibleIssueCount
    visibleNoteCount = Self.fallbackDefaultVisibleNoteCount
    calendarWarnings = []
    googleAuthorizationError = nil
    linearError = nil
    linearTeamError = nil
    githubError = nil
    notesError = nil
    issues = Array(allIssues.prefix(visibleIssueCount))
    notes = Array(allNotes.prefix(visibleNoteCount))
    lastUpdatedAt = Date()
    isRefreshing = false
  }

  /// Compares two dates newest-first and returns `nil` for ties.
  private func compareNewest(_ lhs: Date, _ rhs: Date) -> Bool? {
    guard lhs != rhs else {
      return nil
    }
    return lhs > rhs
  }

  /// Compares two notes by title and returns `nil` for ties.
  private func compareNoteTitle(_ lhs: LocalNoteItem, _ rhs: LocalNoteItem) -> Bool? {
    let comparison = lhs.title.localizedStandardCompare(rhs.title)
    guard comparison != .orderedSame else {
      return nil
    }
    return comparison == .orderedAscending
  }

  /// Compares two notes by stable local identifier.
  private func compareNoteID(_ lhs: LocalNoteItem, _ rhs: LocalNoteItem) -> Bool {
    lhs.id < rhs.id
  }

  /// Compares two issues by Linear priority and returns `nil` for ties.
  private func comparePriority(_ lhs: LinearIssueItem, _ rhs: LinearIssueItem) -> Bool? {
    guard lhs.prioritySortRank != rhs.prioritySortRank else {
      return nil
    }
    return lhs.prioritySortRank < rhs.prioritySortRank
  }

  /// Compares two issues by workflow status and returns `nil` for ties.
  private func compareStatus(_ lhs: LinearIssueItem, _ rhs: LinearIssueItem) -> Bool? {
    guard lhs.stateSortRank != rhs.stateSortRank else {
      return nil
    }
    return lhs.stateSortRank < rhs.stateSortRank
  }

  /// Compares two issues by due date and returns `nil` for ties.
  private func compareDueDate(_ lhs: LinearIssueItem, _ rhs: LinearIssueItem) -> Bool? {
    switch (lhs.dueDate, rhs.dueDate) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
      return lhsDate < rhsDate
    case (nil, _?):
      return false
    case (_?, nil):
      return true
    default:
      return nil
    }
  }

  /// Compares two issues by title and returns `nil` for ties.
  private func compareTitle(_ lhs: LinearIssueItem, _ rhs: LinearIssueItem) -> Bool? {
    let comparison = lhs.title.localizedStandardCompare(rhs.title)
    guard comparison != .orderedSame else {
      return nil
    }
    return comparison == .orderedAscending
  }

  /// Compares two issues by stable Linear identifier.
  private func compareID(_ lhs: LinearIssueItem, _ rhs: LinearIssueItem) -> Bool {
    lhs.id < rhs.id
  }

  /// Normalizes a user-selected hotkey to a single lowercase character.
  private static func normalizedHotkey(_ hotkey: String?, defaultValue: String) -> String {
    hotkey?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .first
      .map(String.init) ?? defaultValue
  }

  /// Matches raw key input without converting empty input into an action default.
  static func hotkeyMatches(_ input: String, configured: String) -> Bool {
    guard let character = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().first else {
      return false
    }
    return String(character) == configured
  }

  /// Repairs persisted hover shortcuts in precedence order so every action remains reachable.
  static func repairedHoverHotkeys(
    copy: String?,
    status: String?,
    priority: String?,
    dueDate: String?,
    label: String? = nil,
    assignee: String? = nil
  ) -> [String] {
    let preferred = [
      normalizedHotkey(copy, defaultValue: "c"),
      normalizedHotkey(status, defaultValue: "s"),
      normalizedHotkey(priority, defaultValue: "p"),
      normalizedHotkey(dueDate, defaultValue: "d"),
      normalizedHotkey(label, defaultValue: "l"),
      normalizedHotkey(assignee, defaultValue: "a")
    ]
    let fallbacks = [
      ["c", "l", "k", "y"],
      ["s", "w", "u", "d"],
      ["p", "r", "i", "o"],
      ["d", "e", "t", "x"],
      ["l", "f", "g", "b"],
      ["a", "q", "v", "z"]
    ]
    var used = Set<String>()
    return preferred.enumerated().map { index, candidate in
      let repaired = used.contains(candidate)
        ? fallbacks[index].first(where: { !used.contains($0) }) ?? candidate
        : candidate
      used.insert(repaired)
      return repaired
    }
  }

  /// Returns a persisted integer or the supplied default when the key is unset.
  private static func storedInteger(forKey key: String, defaultValue: Int) -> Int {
    guard UserDefaults.standard.object(forKey: key) != nil else {
      return defaultValue
    }
    return UserDefaults.standard.integer(forKey: key)
  }

  /// Keeps the pre-meeting title window in a practical Settings range.
  private static func clampedMenuBarLeadTime(_ minutes: Int) -> Int {
    min(max(minutes, 0), 240)
  }

  /// Keeps the post-start title window in a practical Settings range.
  private static func clampedMenuBarPostStartGrace(_ minutes: Int) -> Int {
    min(max(minutes, 0), 60)
  }

  /// Keeps the default note count in a practical menu range.
  private static func clampedDefaultVisibleNoteCount(_ count: Int) -> Int {
    min(max(count, 1), 25)
  }

  /// Loads all enabled calendars, preserving successful results when individual sources fail.
  private func loadGoogleAgenda(now: Date = Date()) async -> CalendarAgendaLoadResult {
    let calendar = Calendar.current
    let tomorrowStart = calendar.date(
      byAdding: .day,
      value: 1,
      to: calendar.startOfDay(for: now)
    ) ?? now.addingTimeInterval(24 * 60 * 60)
    let dayAfterTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrowStart)
      ?? tomorrowStart.addingTimeInterval(24 * 60 * 60)
    let contexts = googleAccounts
      .filter(\.isConnected)
      .flatMap { status in
        status.account.calendars
          .filter(\.isEnabled)
          .map { source in
            GoogleCalendarFetchContext(
              accountID: status.id,
              accountLabel: status.account.label,
              calendar: source,
              service: CalendarService(authSession: googleSession(for: status.account))
            )
          }
      }

    var sourceBatches: [CalendarAgendaSourceBatch] = []
    let accountWarnings = googleAccounts.compactMap { status -> String? in
      guard status.isConnected, let detail = status.detail, !detail.isEmpty else { return nil }
      return "\(status.account.label): \(detail)"
    }
    var reauthenticationAccountIDs: Set<UUID> = []

    await withTaskGroup(of: GoogleCalendarFetchOutcome.self) { group in
      for context in contexts {
        group.addTask {
          do {
            let events = try await context.service.fetchEvents(
              accountID: context.accountID,
              calendar: context.calendar,
              from: now,
              to: dayAfterTomorrow,
              cutoff: now
            )
            return GoogleCalendarFetchOutcome(context: context, events: events, error: nil, needsReauthentication: false)
          } catch {
            return GoogleCalendarFetchOutcome(
              context: context,
              events: [],
              error: error.localizedDescription,
              needsReauthentication: requiresGoogleReauthentication(error)
            )
          }
        }
      }

      for await outcome in group {
        sourceBatches.append(CalendarAgendaSourceBatch(
          events: outcome.events,
          warning: outcome.error.map {
            "\(outcome.context.calendar.name) (\(outcome.context.accountLabel)): \($0)"
          }
        ))
        if outcome.needsReauthentication {
          reauthenticationAccountIDs.insert(outcome.context.accountID)
        }
      }
    }

    return Self.assembleCalendarAgenda(
      sourceBatches: sourceBatches,
      additionalWarnings: accountWarnings,
      reauthenticationAccountIDs: reauthenticationAccountIDs,
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow
    )
  }

  /// Merges successful source batches without allowing sibling warnings to hide them.
  static func assembleCalendarAgenda(
    sourceBatches: [CalendarAgendaSourceBatch],
    additionalWarnings: [String] = [],
    reauthenticationAccountIDs: Set<UUID> = [],
    tomorrowStart: Date,
    dayAfterTomorrow: Date
  ) -> CalendarAgendaLoadResult {
    let sections = CalendarEventItem.agendaSections(
      from: sourceBatches.flatMap(\.events),
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: Self.todayEventLimit,
      tomorrowLimit: Self.tomorrowEventLimit
    )
    let warnings = additionalWarnings + sourceBatches.compactMap(\.warning)
    return CalendarAgendaLoadResult(
      sourceEvents: sourceBatches.flatMap(\.events),
      today: sections.today,
      tomorrow: sections.tomorrow,
      warnings: Array(Set(warnings)).sorted(),
      reauthenticationAccountIDs: reauthenticationAccountIDs,
      shouldReplaceEvents: sourceBatches.isEmpty || sourceBatches.contains { $0.warning == nil }
    )
  }

  /// Rebuilds the visible agenda after a local source is disabled or disconnected.
  private func rebuildAgendaFromCachedGoogleSources(now: Date = Date()) {
    let calendar = Calendar.current
    let tomorrowStart = calendar.date(
      byAdding: .day,
      value: 1,
      to: calendar.startOfDay(for: now)
    ) ?? now.addingTimeInterval(24 * 60 * 60)
    let dayAfterTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrowStart)
      ?? tomorrowStart.addingTimeInterval(24 * 60 * 60)
    let sections = CalendarEventItem.agendaSections(
      from: googleSourceEvents,
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: Self.todayEventLimit,
      tomorrowLimit: Self.tomorrowEventLimit
    )
    events = sections.today
    tomorrowEvents = sections.tomorrow
  }

  /// Loads Linear issues and packages thrown errors as `Result`.
  private func loadLinearIssues() async -> Result<[LinearIssueItem], Error> {
    do {
      return .success(try await fetchLinearIssues())
    } catch {
      return .failure(error)
    }
  }

  /// Loads open GitHub issues matching the configured filter.
  private func loadGitHubIssues() async -> Result<[GitHubIssueItem], Error> {
    do {
      return .success(try await fetchGitHubIssues())
    } catch {
      return .failure(error)
    }
  }

  /// Fetches Linear issues matching the configured assignee filter.
  private func fetchLinearIssues() async throws -> [LinearIssueItem] {
    switch linearIssueFilter {
    case .assignedToMe:
      return try await linearService.fetchAssignedIssues(enabledTeamIDs: linearIssueTeamFilter)
    case .allOpen:
      return try await linearService.fetchOpenIssues(enabledTeamIDs: linearIssueTeamFilter)
    }
  }

  /// Fetches GitHub issues matching the configured assignee filter.
  private func fetchGitHubIssues() async throws -> [GitHubIssueItem] {
    switch githubIssueFilter {
    case .assignedToMe:
      return try await githubService.fetchAssignedIssues(enabledRepositories: enabledGitHubRepositories)
    case .allOpen:
      return try await githubService.fetchOpenIssues(enabledRepositories: enabledGitHubRepositories)
    }
  }

}

/// Immutable context for one enabled calendar fetch.
private struct GoogleCalendarFetchContext: Sendable {
  let accountID: UUID
  let accountLabel: String
  let calendar: GoogleCalendarSource
  let service: CalendarService
}

/// Success or failure from one enabled calendar without aborting sibling fetches.
private struct GoogleCalendarFetchOutcome: Sendable {
  let context: GoogleCalendarFetchContext
  let events: [CalendarEventItem]
  let error: String?
  let needsReauthentication: Bool
}

/// Successful events and an optional warning produced by one independent source.
struct CalendarAgendaSourceBatch: Sendable {
  let events: [CalendarEventItem]
  let warning: String?
}

/// Fully merged agenda and recoverable source failures from one refresh.
struct CalendarAgendaLoadResult: Sendable {
  let sourceEvents: [CalendarEventItem]
  let today: [CalendarEventItem]
  let tomorrow: [CalendarEventItem]
  let warnings: [String]
  let reauthenticationAccountIDs: Set<UUID>
  let shouldReplaceEvents: Bool
}

/// Recognizes OAuth failures that invalidate only the affected Google account.
private func requiresGoogleReauthentication(_ error: Error) -> Bool {
  guard let oauthError = error as? OAuthError else { return false }
  switch oauthError {
  case .reauthenticationRequired, .notSignedIn, .refreshFailed:
    return true
  default:
    return false
  }
}

/// Errors produced by local store operations.
private enum StatusStoreError: LocalizedError {
  /// The requested local note no longer exists in memory.
  case missingLocalNote

  /// A reconnect flow authenticated a different Google identity.
  case googleAccountMismatch(expected: String, actual: String)

  /// Human-readable local store error text.
  var errorDescription: String? {
    switch self {
    case .missingLocalNote:
      "This note was deleted before it could be saved."
    case .googleAccountMismatch(let expected, let actual):
      "Expected \(expected), but Google signed in as \(actual)."
    }
  }
}
