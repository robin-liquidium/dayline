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

  /// Calendar loading error shown as a compact status row.
  @Published private(set) var calendarError: String?

  /// Linear loading error shown as a compact status row.
  @Published private(set) var linearError: String?

  /// Installation/authentication state for required local CLIs.
  @Published private(set) var dependencyStatuses = DependencyStatus.checkingAll

  /// Whether a refresh is currently running.
  @Published private(set) var isRefreshing = false

  /// Time when the last refresh completed successfully or partially.
  @Published private(set) var lastUpdatedAt: Date?

  /// Current clock tick used for menu bar countdown text.
  @Published private var menuBarClockDate = Date()

  /// Identifier for the Linear issue currently under the pointer.
  @Published private(set) var hoveredIssueID: LinearIssueItem.ID?

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

  private static let initialVisibleIssueCount = 6
  private static let issuePageSize = 10
  private static let refreshIntervalKey = "refreshIntervalMinutes"
  private static let copyIssueHotkeyKey = "copyIssueHotkey"
  private static let statusPickerHotkeyKey = "statusPickerHotkey"
  private static let priorityPickerHotkeyKey = "priorityPickerHotkey"
  private static let linearIssueOrderKey = "linearIssueOrder"
  private static let menuBarEventLeadTimeKey = "menuBarEventLeadTimeMinutes"
  private static let menuBarEventPostStartGraceKey = "menuBarEventPostStartGraceMinutes"
  private static let defaultMenuBarEventLeadTimeMinutes = 30
  private static let defaultMenuBarEventPostStartGraceMinutes = 5
  private static let menuBarClockRefreshSeconds: TimeInterval = 15

  private let calendarService: CalendarService
  private let linearService: LinearService
  private let dependencyService: DependencyService
  private var allIssues: [LinearIssueItem] = []
  private var refreshTimer: Timer?
  private var menuBarClockTimer: Timer?

  /// Creates a live store and immediately starts the background refresh loop.
  init(
    calendarService: CalendarService = CalendarService(),
    linearService: LinearService = LinearService(),
    dependencyService: DependencyService = DependencyService()
  ) {
    self.calendarService = calendarService
    self.linearService = linearService
    self.dependencyService = dependencyService
    self.refreshIntervalMinutes = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
    self.copyIssueHotkey = Self.normalizedHotkey(UserDefaults.standard.string(forKey: Self.copyIssueHotkeyKey), defaultValue: "c")
    self.statusPickerHotkey = Self.normalizedHotkey(UserDefaults.standard.string(forKey: Self.statusPickerHotkeyKey), defaultValue: "s")
    self.priorityPickerHotkey = Self.normalizedHotkey(UserDefaults.standard.string(forKey: Self.priorityPickerHotkeyKey), defaultValue: "p")
    self.linearIssueOrder = LinearIssueOrder(rawValue: UserDefaults.standard.string(forKey: Self.linearIssueOrderKey) ?? "") ?? .priority
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
    scheduleRefreshTimer()
    scheduleMenuBarClockTimer()
    Task { await refresh() }
  }

  deinit {
    refreshTimer?.invalidate()
    menuBarClockTimer?.invalidate()
  }

  /// Refreshes dependency, calendar, and Linear data.
  func refresh() async {
    guard !isRefreshing else {
      return
    }

    isRefreshing = true
    await refreshDependencyStatus()

    async let calendarResult: Result<[CalendarEventItem], Error>? = isDependencyReady(.googleWorkspace) ? loadCalendarEvents() : nil
    async let tomorrowCalendarResult: Result<[CalendarEventItem], Error>? = isDependencyReady(.googleWorkspace) ? loadTomorrowCalendarEvents() : nil
    async let linearResult: Result<[LinearIssueItem], Error>? = isDependencyReady(.linear) ? loadLinearIssues() : nil

    switch await calendarResult {
    case .success(let fetchedEvents)?:
      events = fetchedEvents
      calendarError = nil
    case .failure(let error)?:
      calendarError = error.localizedDescription
    case nil:
      events = []
      tomorrowEvents = []
      calendarError = nil
    }

    switch await tomorrowCalendarResult {
    case .success(let fetchedEvents)?:
      tomorrowEvents = fetchedEvents
    case .failure(let error)?:
      if calendarError == nil {
        calendarError = error.localizedDescription
      }
    case nil:
      break
    }

    switch await linearResult {
    case .success(let fetchedIssues)?:
      allIssues = fetchedIssues
      applyLinearIssueOrder()
      linearError = nil
    case .failure(let error)?:
      linearError = error.localizedDescription
    case nil:
      allIssues = []
      applyLinearIssueOrder()
      linearError = nil
    }

    lastUpdatedAt = Date()
    isRefreshing = false
  }

  /// Rechecks install/auth state for the local CLIs.
  func refreshDependencyStatus() async {
    dependencyStatuses = DependencyStatus.checkingAll
    dependencyStatuses = await dependencyService.checkAll()
  }

  /// Dependencies that need user setup.
  var dependencySetupItems: [DependencyStatus] {
    dependencyStatuses.filter { status in
      status.state != .ready
    }
  }

  /// Whether the setup section should be visible.
  var hasDependencySetupItems: Bool {
    !dependencySetupItems.isEmpty
  }

  /// Persists a new refresh cadence selected from Settings.
  func setRefreshInterval(minutes: Int) {
    refreshIntervalMinutes = minutes
  }

  /// Opens a dependency install command in Terminal.
  func installDependency(_ status: DependencyStatus) {
    TerminalLauncher.run(status.kind.installCommand)
  }

  /// Opens a dependency auth command in Terminal.
  func authenticateDependency(_ status: DependencyStatus) {
    TerminalLauncher.run(status.kind.authCommand)
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

    do {
      let updatedIssue = try await linearService.updateIssuePriority(issueID: issueID, priority: priority.value)
      replaceFetchedIssue(updatedIssue)
      linearError = nil
    } catch {
      linearError = error.localizedDescription
    }

    updatingPriorityIssueID = nil
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

  /// Returns whether one dependency is currently ready.
  private func isDependencyReady(_ kind: DependencyKind) -> Bool {
    dependencyStatuses.first { $0.kind == kind }?.isReady == true
  }

  /// Returns the event that should currently replace the menu bar icon.
  private func menuBarEvent(at now: Date) -> CalendarEventItem? {
    let leadTime = TimeInterval(menuBarEventLeadTimeMinutes * 60)
    let postStartGrace = TimeInterval(menuBarEventPostStartGraceMinutes * 60)

    return events.first { event in
      now >= event.startDate.addingTimeInterval(-leadTime)
        && now <= event.startDate.addingTimeInterval(postStartGrace)
    }
  }

  /// Applies the selected Linear ordering to fetched issue candidates.
  private func applyLinearIssueOrder() {
    issues = sortedLinearIssues(allIssues)
      .prefix(visibleIssueCount)
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

  /// Loads calendar events and packages thrown errors as `Result`.
  private func loadCalendarEvents() async -> Result<[CalendarEventItem], Error> {
    do {
      return .success(try await calendarService.fetchUpcomingEvents())
    } catch {
      return .failure(error)
    }
  }

  /// Loads tomorrow's calendar events and packages thrown errors as `Result`.
  private func loadTomorrowCalendarEvents() async -> Result<[CalendarEventItem], Error> {
    do {
      return .success(try await calendarService.fetchTomorrowEvents())
    } catch {
      return .failure(error)
    }
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
