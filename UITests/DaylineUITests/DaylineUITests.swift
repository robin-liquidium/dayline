import XCTest

final class DaylineUITests: XCTestCase {
  private var app: XCUIApplication!
  private let complexMarkdownNote = """
  # Markdown regression

  This longer paragraph has *italic words*, **bold words**, and ***bold italic words*** without losing text.

  * First bullet with *nested emphasis*
  * Second bullet with **strong text**
  * Third bullet remains visible after a long wrapping sentence with emoji 🚀 and café.
  """

  private var runID: String {
    ProcessInfo.processInfo.environment["DAYLINE_UI_TEST_RUN_ID"] ?? "local-xcode-run"
  }

  override func setUpWithError() throws {
    continueAfterFailure = false

    let sourceFileURL = URL(fileURLWithPath: #filePath)
    let repositoryURL = sourceFileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let appURL = repositoryURL.appending(path: "dist/Dayline Mock.app")
    guard FileManager.default.fileExists(atPath: appURL.path) else {
      throw XCTSkip("Dayline mock app does not exist at \(appURL.path)")
    }

    app = XCUIApplication(url: appURL)
    app.launchArguments = ["--mock", "--ui-testing", "-AppleShowScrollBars", "Always"]
    if let testRunID = ProcessInfo.processInfo.environment["DAYLINE_UI_TEST_RUN_ID"] {
      app.launchArguments += ["--ui-test-run-id", testRunID]
    }
    if let logDirectory = ProcessInfo.processInfo.environment["DAYLINE_UI_TEST_LOG_DIR"] {
      app.launchArguments += ["--ui-test-log-dir", logDirectory]
    }
    app.launch()
    let running = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let application = object as? XCUIApplication else { return false }
        return application.state != .notRunning
      },
      object: app
    )
    XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 10), .completed)
  }

  override func tearDownWithError() throws {
    app?.terminate()
    app = nil
  }

  func testMenuShowsCoreSectionsAndTomorrowEvents() throws {
    try XCTContext.runActivity(named: "Open menu and verify core sections") { _ in
      try openMenu()

      assertExists("dayline.refresh")
      assertExists("dayline.settings")
      assertExists("dayline.quit")
      let updateButton = element("dayline.update")
      assertExists("dayline.update")
      XCTAssertFalse(updateButton.isEnabled, "Mock Update button should not advertise an unavailable action")
      assertExists("calendar.event.mock-standup")
      assertExists("linear.issue.DAY-104")
      assertExists("issues.source.reminders")
      assertExists("notes.note.mock-note-1")
      assertNoVisibleHorizontalScrollBars()
      element("dayline.refresh").click()
      assertExists("dayline.refresh")
      attachCheckpoint(
        "core-menu",
        identifiers: [
          "dayline.refresh", "dayline.settings", "dayline.quit", "dayline.update",
          "calendar.event.mock-standup", "linear.issue.DAY-104", "notes.note.mock-note-1",
        ]
      )
    }

    XCTContext.runActivity(named: "Expand and collapse tomorrow events") { _ in
      element("calendar.tomorrow.toggle").click()
      assertExists("calendar.event.mock-planning")
      attachCheckpoint(
        "tomorrow-expanded",
        identifiers: ["calendar.tomorrow.toggle", "calendar.event.mock-planning"]
      )

      element("calendar.tomorrow.toggle").click()
      XCTAssertFalse(element("calendar.event.mock-planning").waitForExistence(timeout: 1))
      attachCheckpoint(
        "tomorrow-collapsed",
        identifiers: ["calendar.tomorrow.toggle", "calendar.event.mock-planning"]
      )
    }
  }

  func testIssueSourceSwitchingPickersAndPagination() throws {
    try openMenu()

    XCTContext.runActivity(named: "Switch from Linear to GitHub and back") { _ in
      element("issues.source.github").click()
      assertExists("github.issue.mock-gh-1")
      XCTAssertFalse(element("linear.issue.DAY-104").waitForExistence(timeout: 1))
      attachCheckpoint(
        "github-issues",
        identifiers: ["issues.source.github", "github.issue.mock-gh-1", "linear.issue.DAY-104"]
      )

      element("issues.source.linear").click()
      assertExists("linear.issue.DAY-104")
      assertExists("linear.showMore")
      XCTAssertFalse(element("linear.issue.DAY-121").exists)

      element("issues.source.reminders").click()
      assertExists("reminders.issue.mock-reminder-1")
      XCTAssertFalse(element("linear.issue.DAY-104").waitForExistence(timeout: 1))
      XCTAssertFalse(element("github.issue.mock-gh-1").waitForExistence(timeout: 1))

      element("issues.source.linear").click()
      assertExists("linear.issue.DAY-104")
    }

    XCTContext.runActivity(named: "Expand Linear issue pagination") { _ in
      element("linear.showMore").click()
      assertExists("linear.issue.DAY-121")
      assertExists("linear.showLess")
      attachCheckpoint(
        "linear-expanded",
        identifiers: ["issues.source.linear", "linear.issue.DAY-104", "linear.issue.DAY-121", "linear.showLess"]
      )

      element("linear.showLess").click()
      XCTAssertFalse(element("linear.issue.DAY-121").waitForExistence(timeout: 1))
    }

    XCTContext.runActivity(named: "Change Linear priority") { _ in
      let issue = element("linear.issue.DAY-104")
      issue.hover()
      app.typeKey("p", modifierFlags: [])
      assertExists("linear.priority.4")
      element("linear.priority.4").click()

      issue.hover()
      app.typeKey("p", modifierFlags: [])
      assertExists("linear.priority.4")
      assertValue(of: element("linear.priority.4"), equals: "Selected")
      let lowPrioritySelected = element("linear.priority.4").value as? String == "Selected"
      XCTAssertTrue(lowPrioritySelected)
      app.typeKey(.escape, modifierFlags: [])

      attachCheckpoint(
        "linear-priority-updated",
        identifiers: ["linear.issue.DAY-104"],
        facts: ["low_priority_option_selected=\(lowPrioritySelected)"]
      )
    }

    XCTContext.runActivity(named: "Change Linear due date through generalized picker state") { _ in
      let issue = element("linear.issue.DAY-104")
      XCTAssertTrue((issue.label as String).contains("Due"))
      issue.hover()
      app.typeKey("d", modifierFlags: [])
      assertExists("linear.dueDate.remove.DAY-104")
      element("linear.dueDate.remove.DAY-104").click()
      assertLabel(of: issue, doesNotContain: "Due")
    }

    XCTContext.runActivity(named: "Change Linear labels and assignee") { _ in
      let issue = element("linear.issue.DAY-104")
      issue.hover()
      app.typeKey("l", modifierFlags: [])
      assertExists("issue.label.mock-label-bug")
      element("issue.label.mock-label-bug").click()
      assertValue(of: element("issue.label.mock-label-bug"), equals: "Selected")
      let bugLabelSelected = element("issue.label.mock-label-bug").value as? String == "Selected"
      app.typeKey(.escape, modifierFlags: [])

      let statusIssue = element("linear.issue.DAY-112")
      statusIssue.hover()
      app.typeKey("s", modifierFlags: [])
      assertExists("linear.status.mock-done")
      element("linear.status.mock-done").click()
      let completedIssueRemovedFromOpenList = waitForRemoval(statusIssue)

      issue.hover()
      app.typeKey("a", modifierFlags: [])
      assertExists("issue.assignee.mock-user")
      element("issue.assignee.mock-user").click()
      let reassignedIssueRemovedFromMyIssues = waitForRemoval(issue)

      attachCheckpoint(
        "linear-pickers-updated",
        identifiers: ["linear.showMore"],
        facts: [
          "bug_label_option_selected=\(bugLabelSelected)",
          "completed_issue_removed_from_open_list=\(completedIssueRemovedFromOpenList)",
          "reassigned_issue_removed_from_my_issues=\(reassignedIssueRemovedFromMyIssues)",
        ]
      )
    }
  }

  func testAppleReminderPickersPreviewAndCompletion() throws {
    try openMenu()
    element("issues.source.reminders").click()

    let reminder = element("reminders.issue.mock-reminder-1")
    assertExists("reminders.issue.mock-reminder-1")

    openReminderHoverAction(on: reminder, expected: "reminders.preview.mock-reminder-1") {
      app.typeKey(.space, modifierFlags: [])
    }
    app.typeKey(.escape, modifierFlags: [])

    openReminderHoverAction(on: reminder, expected: "reminders.priority.9") {
      app.typeKey("p", modifierFlags: [])
    }
    element("reminders.priority.9").click()

    openReminderHoverAction(on: reminder, expected: "reminders.priority.9") {
      app.typeKey("p", modifierFlags: [])
    }
    assertValue(of: element("reminders.priority.9"), equals: "Selected")
    app.typeKey(.escape, modifierFlags: [])

    openReminderHoverAction(on: reminder, expected: "reminders.dueDate.remove.mock-reminder-1") {
      app.typeKey("d", modifierFlags: [])
    }
    element("reminders.dueDate.remove.mock-reminder-1").click()
    assertLabel(of: reminder, doesNotContain: "Due")
    openReminderHoverAction(on: reminder, expected: "reminders.dueDate.calendar.mock-reminder-1") {
      app.typeKey("d", modifierFlags: [])
    }
    XCTAssertFalse(element("reminders.dueDate.remove.mock-reminder-1").exists)
    app.typeKey(.escape, modifierFlags: [])

    reminder.hover()
    app.typeKey("l", modifierFlags: [])
    XCTAssertFalse(element("issue.label.mock-label-bug").waitForExistence(timeout: 1))
    app.typeKey("a", modifierFlags: [])
    XCTAssertFalse(element("issue.assignee.mock-user").waitForExistence(timeout: 1))

    let recurring = element("reminders.issue.mock-reminder-2")
    recurring.hover()
    app.typeKey("d", modifierFlags: [])
    XCTAssertFalse(element("reminders.dueDate.calendar.mock-reminder-2").waitForExistence(timeout: 1))

    if element("reminders.showMore").exists {
      element("reminders.showMore").click()
    }
    let readOnly = element("reminders.issue.mock-reminder-6")
    scrollIntoView(readOnly)
    readOnly.hover()
    app.typeKey("s", modifierFlags: [])
    XCTAssertFalse(element("reminders.status.completed").waitForExistence(timeout: 1))
    app.typeKey("p", modifierFlags: [])
    XCTAssertFalse(element("reminders.priority.9").waitForExistence(timeout: 1))
    app.typeKey("d", modifierFlags: [])
    XCTAssertFalse(element("reminders.dueDate.calendar.mock-reminder-6").waitForExistence(timeout: 1))

    scrollIntoView(reminder)
    openReminderHoverAction(on: reminder, expected: "reminders.status.completed") {
      app.typeKey("s", modifierFlags: [])
    }
    element("reminders.status.completed").click()
    waitForRemoval(reminder)

    attachCheckpoint(
      "apple-reminder-actions",
      identifiers: ["issues.source.reminders", "reminders.issue.mock-reminder-2"],
      facts: ["preview_opened=true", "priority_changed=true", "due_date_removed=true", "completed=true"]
    )
  }

  func testRemindersOnlyUsesSingleProviderHeading() throws {
    app.terminate()
    app.launchArguments.append("--mock-issue-providers=reminders")
    app.launch()
    try openMenu()

    assertExists("reminders.new")
    assertExists("reminders.issue.mock-reminder-1")
    XCTAssertFalse(element("issues.source.reminders").exists)
    XCTAssertFalse(element("linear.new").exists)
    XCTAssertFalse(element("github.new").exists)
    XCTAssertFalse(element("linear.issue.DAY-104").exists)
    XCTAssertFalse(element("github.issue.mock-gh-1").exists)
    assertNoVisibleHorizontalScrollBars()
  }

  func testSwipeRevealActions() throws {
    try openMenu()

    let issue = element("linear.issue.DAY-112")
    XCTAssertFalse(element("linear.cancel.DAY-112").exists)
    revealDestructiveAction(on: issue)
    let cancelIssueButton = element("linear.cancel.DAY-112")
    XCTAssertTrue(cancelIssueButton.waitForExistence(timeout: 5))
    assertNoVisibleHorizontalScrollBars()
    cancelIssueButton.click()
    let linearConfirmationButtons = app.buttons.matching(NSPredicate(
      format: "NOT (identifier BEGINSWITH %@)",
      "linear.cancel."
    ))
    let confirmCancellation = linearConfirmationButtons["Cancel Linear issue"].firstMatch
    assertEnabled(confirmCancellation, description: "Linear issue cancellation confirmation button")
    confirmCancellation.click()
    try openMenu()
    waitForRemoval(issue)

    element("issues.source.reminders").click()
    let reminder = element("reminders.issue.mock-reminder-1")
    XCTAssertFalse(element("reminders.delete.mock-reminder-1").exists)
    revealDestructiveAction(on: reminder)
    let deleteButton = element("reminders.delete.mock-reminder-1")
    XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
    assertNoVisibleHorizontalScrollBars()
    deleteButton.click()
    let confirmationButtons = app.buttons.matching(NSPredicate(
      format: "NOT (identifier BEGINSWITH %@)",
      "reminders.delete."
    ))
    let confirmButton = confirmationButtons["Delete Apple Reminder"].firstMatch
    assertEnabled(confirmButton, description: "Apple Reminder deletion confirmation button")
    confirmButton.click()
    try openMenu()
    waitForRemoval(reminder)
  }

  func testDestructiveActionsCancelAndConfirm() throws {
    try openMenu()
    assertNoVisibleHorizontalScrollBars()

    XCTContext.runActivity(named: "Cancel then confirm Linear issue cancellation") { _ in
      let issue = element("linear.issue.DAY-112")
      issue.rightClick()
      assertExists("linear.cancelContext.DAY-112")
      element("linear.cancelContext.DAY-112").click()
      let cancelButton = app.buttons["Cancel"].firstMatch
      XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
      cancelButton.click()
      try? openMenu()
      assertExists("linear.issue.DAY-112")

      issue.rightClick()
      assertExists("linear.cancelContext.DAY-112")
      element("linear.cancelContext.DAY-112").click()
      let confirmButton = app.buttons["Cancel Linear issue"].firstMatch
      XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
      confirmButton.click()
      try? openMenu()
      waitForRemoval(issue)
    }

    XCTContext.runActivity(named: "Cancel then confirm note deletion") { _ in
      let note = element("notes.note.mock-note-2")
      scrollIntoView(note)
      note.rightClick()
      assertExists("notes.deleteContext.mock-note-2")
      element("notes.deleteContext.mock-note-2").click()
      let cancelButton = app.buttons["Cancel"].firstMatch
      XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
      cancelButton.click()
      try? openMenu()
      scrollIntoView(note)
      assertExists("notes.note.mock-note-2")

      note.rightClick()
      assertExists("notes.deleteContext.mock-note-2")
      element("notes.deleteContext.mock-note-2").click()
      let nonRowActionButtons = app.buttons.matching(NSPredicate(
        format: "NOT (identifier BEGINSWITH %@)",
        "notes.delete."
      ))
      let confirmButton = nonRowActionButtons["Delete note"].firstMatch
      assertEnabled(confirmButton, description: "Delete note confirmation button")
      confirmButton.click()
      try? openMenu()
      scrollIntoView(element("notes.note.mock-note-1"))
      waitForRemoval(element("notes.note.mock-note-2"))

      attachCheckpoint(
        "destructive-actions",
        identifiers: ["linear.issue.DAY-112", "notes.note.mock-note-1"],
        facts: ["note_deleted=true", "linear_issue_canceled=true"]
      )
    }
  }

  func testDestructiveContextMenusAreAvailable() throws {
    try openMenu()

    let issue = element("linear.issue.DAY-112")
    issue.rightClick()
    assertExists("linear.cancelContext.DAY-112")
    app.typeKey(.escape, modifierFlags: [])

    let note = element("notes.note.mock-note-2")
    scrollIntoView(note)
    note.rightClick()
    assertExists("notes.deleteContext.mock-note-2")
    app.typeKey(.escape, modifierFlags: [])
    assertNoVisibleHorizontalScrollBars()
  }

  func testEditsExistingNote() throws {
    try openMenu()
    let note = element("notes.note.mock-note-1")
    scrollIntoView(note)
    note.click()

    let editor = noteEditor()
    XCTAssertEqual(
      editor.value as? String,
      "Landing page ideas\nTry a warmer background and keep the hero quiet."
    )
    editor.click()
    editor.typeKey("a", modifierFlags: .command)
    editor.typeText("Updated note title\nEdited through XCUITest.")
    element("noteEditor.save").click()

    try openMenu()
    scrollIntoView(element("notes.note.mock-note-1"))
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Updated note title")).firstMatch
        .waitForExistence(timeout: 5)
    )
  }

  func testCreatesLinearGitHubAndAppleReminder() throws {
    try openMenu()

    element("linear.new").click()
    let linearTitle = element("linearEditor.title")
    XCTAssertTrue(linearTitle.waitForExistence(timeout: 5))
    linearTitle.click()
    linearTitle.typeText("Automated Linear issue")
    assertEnabled("linearEditor.create")
    element("linearEditor.create").click()

    try openMenu()
    element("linear.showMore").click()
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", "Automated Linear issue"))
        .firstMatch.waitForExistence(timeout: 5)
    )

    element("issues.source.github").click()
    assertExists("github.issue.mock-gh-1")
    element("github.new").click()
    let githubTitle = element("githubEditor.title")
    XCTAssertTrue(githubTitle.waitForExistence(timeout: 5))
    githubTitle.click()
    githubTitle.typeText("Automated GitHub issue")
    assertEnabled("githubEditor.create")
    element("githubEditor.create").click()

    try openMenu()
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", "Automated GitHub issue"))
        .firstMatch.waitForExistence(timeout: 5)
    )

    element("issues.source.reminders").click()
    assertExists("reminders.issue.mock-reminder-1")
    element("reminders.new").click()
    let reminderTitle = element("reminderEditor.title")
    XCTAssertTrue(reminderTitle.waitForExistence(timeout: 5))
    reminderTitle.click()
    reminderTitle.typeText("Automated Apple Reminder")
    element("reminderEditor.list").click()
    app.menuItems["Personal · iCloud"].click()
    element("reminderEditor.priority").click()
    app.menuItems["Low"].click()
    element("reminderEditor.dueDate.add").click()
    element("reminderEditor.dueTimeEnabled").click()
    let reminderNotes = element("reminderEditor.notes")
    reminderNotes.click()
    reminderNotes.typeText("Created with list, priority, notes, and a timed due date.")
    assertEnabled("reminderEditor.create")
    element("reminderEditor.create").click()

    try openMenu()
    let createdReminder = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "Automated Apple Reminder"))
      .firstMatch
    XCTAssertTrue(createdReminder.waitForExistence(timeout: 5))
    XCTAssertTrue(createdReminder.label.contains("Low"))
    XCTAssertTrue(createdReminder.label.contains("Personal"))
    XCTAssertTrue(createdReminder.label.contains("Due"))
  }

  func testGlobalReminderShortcutOpensCreator() throws {
    app.typeKey("r", modifierFlags: [.control, .option, .command])
    XCTAssertTrue(element("reminderEditor.title").waitForExistence(timeout: 5))
    assertExists("reminderEditor.list")
    assertExists("reminderEditor.priority")
    assertExists("reminderEditor.cancel")
  }

  func testGlobalReminderShortcutExplainsMissingWritableList() throws {
    try openMenu()
    element("dayline.settings").click()
    XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 5))
    let accountsTab = app.staticTexts["Accounts"].firstMatch
    XCTAssertTrue(accountsTab.waitForExistence(timeout: 5))
    accountsTab.click()

    let inboxList = element("settings.account.reminders.list.mock-reminders-work")
    let personalList = element("settings.account.reminders.list.mock-reminders-personal")
    XCTAssertTrue(inboxList.waitForExistence(timeout: 5))
    XCTAssertTrue(personalList.waitForExistence(timeout: 5))
    inboxList.click()
    personalList.click()
    app.typeKey("w", modifierFlags: .command)

    app.typeKey("r", modifierFlags: [.control, .option, .command])
    assertExists("reminderEditor.noWritableList")
    XCTAssertFalse(element("reminderEditor.create").isEnabled)
    assertValue(of: element("reminderEditor.list"), equals: "No writable enabled list selected")
  }

  func testCreatesComplexMarkdownNote() throws {
    try openMenu()
    try XCTContext.runActivity(named: "Create and save a complex Markdown note") { _ in
      element("notes.new").click()

      let editor = noteEditor()
      editor.click()
      typeComplexMarkdownNote(in: editor)
      XCTAssertEqual(editor.value as? String, complexMarkdownNote)
      attachCheckpoint(
        "markdown-note-entered",
        identifiers: ["noteEditor.text", "noteEditor.save"],
        facts: ["raw_text_matches=true"],
        screenshotElement: editor
      )
      element("noteEditor.save").click()

      try openMenu()
      let savedNote = app.buttons
        .matching(NSPredicate(
          format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
          "notes.note.",
          "Markdown regression"
        ))
        .firstMatch
      XCTAssertTrue(savedNote.waitForExistence(timeout: 5))
      attachCheckpoint(
        "markdown-note-saved",
        identifiers: ["notes.new"],
        facts: ["saved_note_visible=\(savedNote.exists)"]
      )
    }
  }

  func testSquareBracketDoesNotAutoClose() throws {
    try openMenu()
    element("notes.new").click()

    let editor = noteEditor()
    let cancelButton = element("noteEditor.cancel")
    XCTAssertLessThanOrEqual(
      editor.frame.maxY,
      cancelButton.frame.minY,
      "The editor must end above the glass controls"
    )
    editor.click()
    editor.typeText("[")
    assertValue(of: editor, equals: "[")

    attachCheckpoint(
      "markdown-no-auto-close",
      identifiers: ["noteEditor.text", "noteEditor.cancel"],
      facts: ["square_bracket_remains_single=true"],
      screenshotElement: editor
    )
  }

  func testKeyboardFormattingShortcuts() throws {
    try openMenu()
    element("notes.new").click()

    let editor = noteEditor()
    editor.click()
    editor.typeText("bold italic")
    let initialValue = try captureValue(of: editor, allowed: ["bold italic", "Bold italic"])
    let firstWord = try XCTUnwrap(initialValue.components(separatedBy: " ").first)
    XCTAssertTrue(firstWord == "bold" || firstWord == "Bold")

    editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
    editor.typeKey("i", modifierFlags: .command)
    assertValue(of: editor, equals: "\(firstWord) *italic*")

    editor.typeKey(.leftArrow, modifierFlags: .command)
    editor.typeKey(.rightArrow, modifierFlags: [.option, .shift])
    editor.typeKey("b", modifierFlags: .command)
    assertValue(of: editor, equals: "**\(firstWord)** *italic*")

    editor.typeKey(.rightArrow, modifierFlags: .command)
    editor.typeKey(.return, modifierFlags: [])
    editor.typeText("list item")
    let formattedPrefix = "**\(firstWord)** *italic*\n"
    let preformattedListValue = try captureValue(
      of: editor,
      allowed: ["\(formattedPrefix)list item", "\(formattedPrefix)List item"]
    )
    let listText = String(preformattedListValue.dropFirst(formattedPrefix.count))
    editor.typeKey("8", modifierFlags: [.command, .shift])
    let formattedListValue = "\(formattedPrefix)- \(listText)"
    assertValue(of: editor, equals: formattedListValue)

    editor.typeKey(.rightArrow, modifierFlags: .command)
    editor.typeKey(.return, modifierFlags: [])
    editor.typeText("link target")
    let linkPrefix = "\(formattedListValue)\n- "
    let preformattedLinkValue = try captureValue(
      of: editor,
      allowed: ["\(linkPrefix)link target", "\(linkPrefix)Link target"]
    )
    let linkText = String(preformattedLinkValue.dropFirst(linkPrefix.count))
    let linkLead = String(linkText.dropLast(" target".count))
    editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
    editor.typeKey("k", modifierFlags: .command)
    let linkURL = app.textFields["URL"].firstMatch
    XCTAssertTrue(linkURL.waitForExistence(timeout: 3))
    linkURL.click()
    linkURL.typeText("https://example.com")
    let insertLink = app.sheets.firstMatch.buttons["Insert"]
    assertEnabled(insertLink, description: "Insert link button")
    insertLink.click()
    assertValue(
      of: editor,
      equals: "\(formattedListValue)\n- \(linkLead) [target](https://example.com)"
    )

    attachCheckpoint(
      "markdown-shortcuts",
      identifiers: ["noteEditor.text", "noteEditor.save"],
      facts: ["bold_shortcut=true", "italic_shortcut=true", "list_shortcut=true", "link_prompt=true"],
      screenshotElement: editor
    )
  }

  func testOpensSettings() throws {
    try openMenu()
    XCTContext.runActivity(named: "Open Settings and verify General controls") { _ in
      element("dayline.settings").click()

      XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 5))
      assertExists("settings.launchAtLogin")
      assertExists("settings.refreshCadence")
      attachCheckpoint(
        "settings-general",
        identifiers: ["settings", "settings.launchAtLogin", "settings.refreshCadence"],
        screenshotElement: app.windows["settings"]
      )

      let calendarTab = app.staticTexts["Calendar"].firstMatch
      XCTAssertTrue(calendarTab.waitForExistence(timeout: 5))
      calendarTab.click()
      assertExists("settings.meetingAlertSnooze")
    }
  }

  func testMeetingAlertShowsCurrentTimeAndSnoozes() throws {
    app.terminate()
    app.launchArguments.append("--mock-meeting-alert")
    app.launch()

    let alert = element("meetingAlert.view")
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    let currentTime = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Current time"))
      .firstMatch
    XCTAssertTrue(currentTime.waitForExistence(timeout: 5))
    XCTAssertFalse((currentTime.value as? String ?? "").isEmpty)
    let snooze = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Snooze ")).firstMatch
    XCTAssertTrue(snooze.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Dismiss"].waitForExistence(timeout: 5))

    snooze.click()
    XCTAssertFalse(alert.waitForExistence(timeout: 2))
  }

  private func openMenu() throws {
    if element("dayline.refresh").exists {
      return
    }

    let statusItem = app.descendants(matching: .statusItem)["dayline.menuBarItem"].firstMatch
    guard statusItem.waitForExistence(timeout: 5) else {
      XCTFail("Dayline menu bar item was not exposed to XCUITest.\n\(app.debugDescription)")
      return
    }

    statusItem.click()
    XCTAssertTrue(element("dayline.refresh").waitForExistence(timeout: 5))
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any)[identifier].firstMatch
  }

  private func openReminderHoverAction(
    on reminder: XCUIElement,
    expected identifier: String,
    trigger: () -> Void
  ) {
    reminder.hover()
    trigger()
    if !element(identifier).waitForExistence(timeout: 1) {
      element("issues.source.reminders").hover()
      reminder.hover()
      trigger()
    }
    assertExists(identifier)
  }

  private func noteEditor() -> XCUIElement {
    XCTAssertTrue(element("noteEditor.text").waitForExistence(timeout: 5))
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    return editor
  }

  private func revealDestructiveAction(on row: XCUIElement) {
    row.hover()
    row.scroll(byDeltaX: -200, deltaY: 0)
    row.scroll(byDeltaX: -200, deltaY: 0)
  }

  private func assertNoVisibleHorizontalScrollBars(
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let menuFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
    let visibleScrollBars = app.scrollBars.allElementsBoundByAccessibilityElement.filter {
      $0.exists
        && !$0.frame.isEmpty
        && $0.frame.width > $0.frame.height
        && $0.frame.intersects(menuFrame)
    }
    XCTAssertTrue(
      visibleScrollBars.isEmpty,
      "Expected no visible horizontal scroll bars with AppleShowScrollBars=Always, found \(visibleScrollBars.count)",
      file: file,
      line: line
    )
  }

  private func scrollIntoView(_ target: XCUIElement) {
    let menuScrollView = app.scrollViews.firstMatch
    XCTAssertTrue(menuScrollView.waitForExistence(timeout: 3))
    let bottomSafetyMargin: CGFloat = 80
    func isSafelyVisible() -> Bool {
      target.isHittable
        && target.frame.maxY <= menuScrollView.frame.maxY - bottomSafetyMargin
    }
    if isSafelyVisible() { return }

    let deadline = Date().addingTimeInterval(3)
    repeat {
      menuScrollView.scroll(byDeltaX: 0, deltaY: -160)
      if isSafelyVisible() { return }
    } while Date() < deadline
    XCTAssertTrue(isSafelyVisible(), "Expected \(target.identifier) to be safely above the scroll view bottom")
  }

  private func assertValue(
    of element: XCUIElement,
    equals expected: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", expected),
      object: element
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: timeout),
      .completed,
      "Expected \(element.identifier) value to equal \(expected), got \(String(describing: element.value))",
      file: file,
      line: line
    )
  }

  private func assertLabel(
    of element: XCUIElement,
    doesNotContain text: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard element.waitForExistence(timeout: timeout) else {
      XCTFail(
        "Expected \(element.identifier) to exist before checking that its label does not contain \(text)",
        file: file,
        line: line
      )
      return
    }

    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "NOT label CONTAINS %@", text),
      object: element
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: timeout),
      .completed,
      "Expected \(element.identifier) label not to contain \(text), got \(element.label)",
      file: file,
      line: line
    )
  }

  private func captureValue(
    of element: XCUIElement,
    allowed: [String],
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> String {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value IN %@", allowed),
      object: element
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: timeout),
      .completed,
      "Expected \(element.identifier) value to be one of \(allowed)",
      file: file,
      line: line
    )
    let value = try XCTUnwrap(element.value as? String, file: file, line: line)
    XCTAssertTrue(allowed.contains(value), file: file, line: line)
    return value
  }

  @discardableResult
  private func waitForRemoval(
    _ element: XCUIElement,
    timeout: TimeInterval = 8,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: element
    )
    let removed = XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    XCTAssertTrue(removed, "Expected \(element.identifier) to disappear", file: file, line: line)
    return removed
  }

  private func assertEnabled(
    _ identifier: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let candidate = element(identifier)
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND enabled == true"),
      object: candidate
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: timeout),
      .completed,
      "Expected accessibility element \(identifier) to become enabled",
      file: file,
      line: line
    )
  }

  private func assertEnabled(
    _ candidate: XCUIElement,
    description: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND enabled == true"),
      object: candidate
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: timeout),
      .completed,
      "Expected \(description) to become enabled",
      file: file,
      line: line
    )
  }

  /// Types list lines as a user would, accepting the editor's auto-continued marker.
  private func typeComplexMarkdownNote(in editor: XCUIElement) {
    let lines = complexMarkdownNote.components(separatedBy: "\n")
    for (index, sourceLine) in lines.enumerated() {
      if index > 0 {
        editor.typeKey(.return, modifierFlags: [])
      }

      let previousLineWasList = index > 0 && lines[index - 1].hasPrefix("* ")
      let line = previousLineWasList && sourceLine.hasPrefix("* ")
        ? String(sourceLine.dropFirst(2))
        : sourceLine
      if !line.isEmpty {
        let characters = Array(line)
        for offset in stride(from: 0, to: characters.count, by: 28) {
          let end = min(offset + 28, characters.count)
          editor.typeText(String(characters[offset..<end]))
        }
      }
    }
  }

  private func attachCheckpoint(
    _ name: String,
    identifiers: [String],
    facts: [String] = [],
    screenshotElement: XCUIElement? = nil
  ) {
    let states = identifiers.map { identifier in
      let candidate = element(identifier)
      return "\(identifier) exists=\(candidate.exists) enabled=\(candidate.exists && candidate.isEnabled)"
    }
    let evidence = (["run_id=\(runID)", "checkpoint=\(name)"] + states + facts).joined(separator: "\n")

    let stateAttachment = XCTAttachment(string: evidence)
    stateAttachment.name = "\(name)-state.txt"
    stateAttachment.lifetime = .keepAlways
    add(stateAttachment)

    let target = screenshotElement ?? app.groups.firstMatch
    let screenshot = target.exists ? target.screenshot() : app.screenshot()
    let screenshotAttachment = XCTAttachment(screenshot: screenshot)
    screenshotAttachment.name = "\(name).png"
    screenshotAttachment.lifetime = .keepAlways
    add(screenshotAttachment)
  }

  private func assertExists(
    _ identifier: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      element(identifier).waitForExistence(timeout: timeout),
      "Expected accessibility element \(identifier)",
      file: file,
      line: line
    )
  }
}
