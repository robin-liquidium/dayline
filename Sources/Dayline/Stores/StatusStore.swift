import AppKit
import Foundation

/// Main actor store that owns refreshed calendar and Linear state for the UI.
@MainActor
final class StatusStore: ObservableObject {
  /// Upcoming timed calendar events for today.
  @Published private(set) var events: [CalendarEventItem] = []

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

  /// Local notes persistence error shown as a compact status row.
  @Published private(set) var notesError: String?

  /// Connection state for Google and Linear accounts.
  @Published private(set) var connectionStatuses = ConnectionStatus.checkingAll

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
  @Published private var menuBarClockDate = Date()

  /// Identifier for the Linear issue currently under the pointer.
  @Published private(set) var hoveredIssueID: LinearIssueItem.ID?

  /// Identifier for the local note currently under the pointer.
  @Published private(set) var hoveredNoteID: LocalNoteItem.ID?

  /// Identifier for the calendar event currently under the pointer.
  @Published private(set) var hoveredEventID: CalendarEventItem.ID?

  /// Identifier for the menu chrome control currently under the pointer.
  @Published private(set) var hoveredControlID: MenuControlID?

  /// Whether tomorrow's calendar events are visible.
  @Published private(set) var isTomorrowExpanded = false

  /// Identifier for the Linear issue whose URL was most recently copied.
  @Published private(set) var copiedIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue whose status picker is open.
  @Published private(set) var statusPickerIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue whose priority picker is open.
  @Published private(set) var priorityPickerIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue currently being updated.
  @Published private(set) var updatingStatusIssueID: LinearIssueItem.ID?

  /// Identifier for the Linear issue whose priority is currently being updated.
  @Published private(set) var updatingPriorityIssueID: LinearIssueItem.ID?

  /// Number of sorted Linear issues currently shown in the menu.
  @Published private(set) var visibleIssueCount = initialVisibleIssueCount

  /// Number of sorted local notes currently shown in the menu.
  @Published private(set) var visibleNoteCount: Int

  /// Keyboard character used to copy the hovered Linear issue link.
  @Published var copyIssueHotkey: String {
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
  @Published var statusPickerHotkey: String {
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
  @Published var priorityPickerHotkey: String {
    didSet {
      let normalizedHotkey = Self.normalizedHotkey(priorityPickerHotkey, defaultValue: "p")
      guard priorityPickerHotkey == normalizedHotkey else {
        priorityPickerHotkey = normalizedHotkey
        return
      }
      UserDefaults.standard.set(priorityPickerHotkey, forKey: Self.priorityPickerHotkeyKey)
    }
  }

  /// User-selected ordering for Linear issues.
  @Published var linearIssueOrder: LinearIssueOrder {
    didSet {
      UserDefaults.standard.set(linearIssueOrder.rawValue, forKey: Self.linearIssueOrderKey)
      applyLinearIssueOrder()
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

  /// Changes when an app-level flow needs to present the Settings window.
  @Published private(set) var settingsPresentationRequestID = UUID()

  /// Stable system image for the menu bar item.
  var menuBarSystemImage: String {
    "calendar"
  }

  /// Optional text that replaces the menu bar icon near a meeting start.
  var menuBarEventText: String? {
    guard let event = menuBarEvent(at: menuBarClockDate) else {
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
  private static let linearIssueOrderKey = "linearIssueOrder"
  private static let localNoteSortOrderKey = "localNoteSortOrder"
  private static let defaultVisibleNoteCountKey = "defaultVisibleNoteCount"
  private static let menuBarEventLeadTimeKey = "menuBarEventLeadTimeMinutes"
  private static let menuBarEventPostStartGraceKey = "menuBarEventPostStartGraceMinutes"
  private static let launchAtLoginDefaultConfiguredKey = "launchAtLoginDefaultConfigured"
  private static let launchAtLoginDefaultPendingKey = "launchAtLoginDefaultPending"
  private static let defaultMenuBarEventLeadTimeMinutes = 30
  private static let defaultMenuBarEventPostStartGraceMinutes = 5
  private static let fallbackDefaultVisibleNoteCount = 3
  private static let menuBarClockRefreshSeconds: TimeInterval = 15
  private static let todayEventLimit = 6
  private static let tomorrowEventLimit = 8

  private let linearService: LinearService
  private let notesService: LocalNotesService
  private let authSessions: [AuthProvider: OAuthSession]
  private let googleAccountRepository: GoogleAccountRepository
  private let launchAtLoginService: LaunchAtLoginService
  private let mockData: MockData?
  private var googleSessions: [UUID: OAuthSession] = [:]
  private var allIssues: [LinearIssueItem] = []
  private var allNotes: [LocalNoteItem] = []
  private var refreshTimer: Timer?
  private var menuBarClockTimer: Timer?
  private var refreshRequested = false

  /// Creates a live store and immediately starts the background refresh loop.
  init(
    linearService: LinearService = LinearService(),
    notesService: LocalNotesService = LocalNotesService(),
    authSessions: [AuthProvider: OAuthSession] = [.linear: .linear],
    googleAccountRepository: GoogleAccountRepository = GoogleAccountRepository(),
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
    self.launchAtLoginService = launchAtLoginService
    self.mockData = mockData
    self.refreshIntervalMinutes = defaults.integer(forKey: Self.refreshIntervalKey)
    self.copyIssueHotkey = Self.normalizedHotkey(UserDefaults.standard.string(forKey: Self.copyIssueHotkeyKey), defaultValue: "c")
    self.statusPickerHotkey = Self.normalizedHotkey(UserDefaults.standard.string(forKey: Self.statusPickerHotkeyKey), defaultValue: "s")
    self.priorityPickerHotkey = Self.normalizedHotkey(UserDefaults.standard.string(forKey: Self.priorityPickerHotkeyKey), defaultValue: "p")
    self.linearIssueOrder = LinearIssueOrder(rawValue: UserDefaults.standard.string(forKey: Self.linearIssueOrderKey) ?? "") ?? .priority
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

    async let calendarResult: CalendarAgendaLoadResult? = hasConnectedGoogleAccount ? loadGoogleAgenda() : nil
    async let linearResult: Result<[LinearIssueItem], Error>? = isConnected(.linear) ? loadLinearIssues() : nil

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
      let previousLabel = connectionStatuses.first(where: { $0.provider == .linear })?.accountLabel
      let accountLabel: String?
      if let previousLabel {
        accountLabel = previousLabel
      } else {
        accountLabel = try? await linearService.fetchAccountLabel()
      }
      guard connectionRevisions[.linear, default: 0] == linearRevision else { return }
      updateConnectionStatus(.linear, state: .connected, detail: nil, accountLabel: accountLabel)
    } else {
      let detail = AuthProvider.linear.isConfigured ? nil : "This build is missing its OAuth client ID."
      updateConnectionStatus(.linear, state: .disconnected, detail: detail, accountLabel: nil)
    }
  }

  /// Providers that still need the user to connect an account.
  var connectionSetupItems: [ConnectionStatus] {
    connectionStatuses.filter { status in
      status.state != .connected && (status.provider != .google || googleAccounts.isEmpty)
    }
  }

  /// Existing Google accounts that need account-specific reauthentication.
  var googleAccountsNeedingAttention: [GoogleAccountStatus] {
    googleAccounts.filter(\.needsAttention)
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

  /// Revokes and removes the stored credentials for one provider.
  func disconnect(_ provider: AuthProvider) async {
    guard mockData == nil else { return }

    if provider == .google {
      for account in googleAccounts {
        await disconnectGoogleAccount(account.id)
      }
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
    copyIssueHotkey = hotkey
  }

  /// Persists a new status picker hotkey selected from Settings.
  func setStatusPickerHotkey(_ hotkey: String) {
    statusPickerHotkey = hotkey
  }

  /// Persists a new priority picker hotkey selected from Settings.
  func setPriorityPickerHotkey(_ hotkey: String) {
    priorityPickerHotkey = hotkey
  }

  /// Persists a new Linear issue ordering and reapplies it immediately.
  func setLinearIssueOrder(_ order: LinearIssueOrder) {
    linearIssueOrder = order
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
    Self.normalizedHotkey(characters, defaultValue: "c") == copyIssueHotkey
  }

  /// Returns whether a keypress should open the status picker.
  func matchesStatusPickerHotkey(_ characters: String) -> Bool {
    Self.normalizedHotkey(characters, defaultValue: "s") == statusPickerHotkey
  }

  /// Returns whether a keypress should open the priority picker.
  func matchesPriorityPickerHotkey(_ characters: String) -> Bool {
    Self.normalizedHotkey(characters, defaultValue: "p") == priorityPickerHotkey
  }

  /// Tracks which Linear issue is currently hovered for keyboard actions.
  func setHoveredIssue(_ issueID: LinearIssueItem.ID?) {
    hoveredIssueID = issueID
  }

  /// Tracks which local note is currently hovered for row highlighting.
  func setHoveredNote(_ noteID: LocalNoteItem.ID?) {
    hoveredNoteID = noteID
  }

  /// Tracks which menu chrome control is currently hovered.
  func setHoveredControl(_ controlID: MenuControlID?) {
    hoveredControlID = controlID
  }

  /// Issue whose status picker should currently be shown.
  var statusPickerIssue: LinearIssueItem? {
    guard let statusPickerIssueID else {
      return nil
    }
    return allIssues.first { $0.id == statusPickerIssueID }
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
    guard let hoveredIssueID,
          allIssues.contains(where: { $0.id == hoveredIssueID }) else {
      return false
    }
    statusPickerIssueID = hoveredIssueID
    priorityPickerIssueID = nil
    return true
  }

  /// Opens the priority picker for the hovered Linear issue.
  @discardableResult
  func presentPriorityPickerForHoveredIssue() -> Bool {
    guard let hoveredIssueID,
          allIssues.contains(where: { $0.id == hoveredIssueID }) else {
      return false
    }
    priorityPickerIssueID = hoveredIssueID
    statusPickerIssueID = nil
    return true
  }

  /// Dismisses the status picker without changing Linear.
  func dismissStatusPicker() {
    statusPickerIssueID = nil
  }

  /// Dismisses the priority picker without changing Linear.
  func dismissPriorityPicker() {
    priorityPickerIssueID = nil
  }

  /// Tracks which calendar event is currently hovered for row highlighting.
  func setHoveredEvent(_ eventID: CalendarEventItem.ID?) {
    hoveredEventID = eventID
  }

  /// Copies the hovered Linear issue URL and briefly marks the row as copied.
  @discardableResult
  func copyHoveredIssueLink() -> Bool {
    guard let hoveredIssueID,
          let issue = issues.first(where: { $0.id == hoveredIssueID }),
          let url = issue.url else {
      return false
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
    copiedIssueID = issue.id

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.4))
      if copiedIssueID == issue.id {
        copiedIssueID = nil
      }
    }

    return true
  }

  /// Changes a Linear issue status and updates the visible list.
  func changeIssueStatus(issueID: LinearIssueItem.ID, state: LinearWorkflowState) async {
    guard updatingStatusIssueID == nil else {
      return
    }

    updatingStatusIssueID = issueID
    statusPickerIssueID = nil

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
          dueDate: issue.dueDate,
          url: issue.url
        ))
      }
      updatingStatusIssueID = nil
      return
    }

    do {
      let updatedIssue = try await linearService.updateIssueStatus(issueID: issueID, stateID: state.id)
      replaceFetchedIssue(updatedIssue)
      linearError = nil
    } catch {
      linearError = error.localizedDescription
    }

    updatingStatusIssueID = nil
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
          dueDate: issue.dueDate,
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

  /// Moves a Linear issue to its team's canceled workflow state.
  func cancelLinearIssue(issueID: LinearIssueItem.ID) async {
    guard updatingStatusIssueID == nil else {
      return
    }

    guard let issue = allIssues.first(where: { $0.id == issueID }),
          let canceledState = issue.workflowStates.first(where: { $0.type == "canceled" }) else {
      linearError = "No canceled Linear state is available for this issue."
      return
    }

    await changeIssueStatus(issueID: issueID, state: canceledState)
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
        dueDate: draft.dueDate.isEmpty ? nil : draft.dueDate,
        url: URL(string: "https://linear.app/dayline")
      ))
      applyLinearIssueOrder()
      lastUpdatedAt = Date()
      return
    }

    try await linearService.createIssue(draft: draft)

    do {
      allIssues = try await linearService.fetchAssignedIssues()
      visibleIssueCount = max(Self.initialVisibleIssueCount, min(visibleIssueCount, allIssues.count))
      applyLinearIssueOrder()
      linearError = nil
    } catch {
      linearError = "Issue created, but refresh failed: \(error.localizedDescription)"
    }

    lastUpdatedAt = Date()
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
    updateConnectionStatus(provider, state: .disconnected, detail: "Sign in again.", accountLabel: nil)
  }

  /// Loads a display label for the connected provider account.
  private func fetchAccountLabel(for provider: AuthProvider) async throws -> String {
    switch provider {
    case .google:
      googleAccounts.first?.account.label ?? "Google Calendar"
    case .linear:
      try await linearService.fetchAccountLabel()
    }
  }

  /// Opens Settings after a successful browser auth so the user can confirm the account.
  private func presentSettingsAfterAuth() {
    settingsPresentationRequestID = UUID()
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
    events = mockData.events
    tomorrowEvents = mockData.tomorrowEvents
    allIssues = mockData.issues
    allNotes = mockData.notes
    connectionStatuses = mockData.connectionStatuses
    googleAccounts = mockData.googleAccounts
    visibleIssueCount = Self.initialVisibleIssueCount
    visibleNoteCount = Self.fallbackDefaultVisibleNoteCount
    calendarWarnings = []
    googleAuthorizationError = nil
    linearError = nil
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
      return .success(try await linearService.fetchAssignedIssues())
    } catch {
      return .failure(error)
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
