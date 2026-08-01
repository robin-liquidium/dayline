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
    app.launchArguments = ["--mock", "--ui-testing"]
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
      assertExists("calendar.event.mock-standup")
      assertExists("linear.issue.DAY-104")
      assertExists("notes.note.mock-note-1")
      element("dayline.refresh").click()
      assertExists("dayline.refresh")
      attachCheckpoint(
        "core-menu",
        identifiers: [
          "dayline.refresh", "dayline.settings", "dayline.quit",
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
      let lowPrioritySelected = !element("linear.priority.4").isEnabled
      XCTAssertTrue(lowPrioritySelected)
      app.typeKey(.escape, modifierFlags: [])

      attachCheckpoint(
        "linear-priority-updated",
        identifiers: ["linear.issue.DAY-104"],
        facts: ["low_priority_option_selected=\(lowPrioritySelected)"]
      )
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
      let completedIssueRemovedFromOpenList = !statusIssue.waitForExistence(timeout: 2)
      XCTAssertTrue(completedIssueRemovedFromOpenList)

      issue.hover()
      app.typeKey("a", modifierFlags: [])
      assertExists("issue.assignee.mock-user")
      element("issue.assignee.mock-user").click()
      let reassignedIssueRemovedFromMyIssues = !issue.waitForExistence(timeout: 2)
      XCTAssertTrue(reassignedIssueRemovedFromMyIssues)

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

  func testSwipeDestructiveActionsCancelAndConfirm() throws {
    try openMenu()

    XCTContext.runActivity(named: "Cancel then confirm Linear issue cancellation") { _ in
      let issue = element("linear.issue.DAY-112")
      revealDestructiveAction(on: issue)
      element("linear.cancel.DAY-112").click()
      let cancelButton = app.buttons["Cancel"].firstMatch
      XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
      cancelButton.click()
      try? openMenu()
      assertExists("linear.issue.DAY-112")

      revealDestructiveAction(on: issue)
      element("linear.cancel.DAY-112").click()
      let confirmButton = app.buttons["Cancel Linear issue"].firstMatch
      XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
      confirmButton.click()
      try? openMenu()
      XCTAssertFalse(issue.waitForExistence(timeout: 2))
    }

    XCTContext.runActivity(named: "Cancel then confirm note deletion") { _ in
      let note = element("notes.note.mock-note-2")
      scrollIntoView(note)
      revealDestructiveAction(on: note)
      element("notes.delete.mock-note-2").click()
      let cancelButton = app.buttons["Cancel"].firstMatch
      XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
      cancelButton.click()
      try? openMenu()
      scrollIntoView(note)
      assertExists("notes.note.mock-note-2")

      revealDestructiveAction(on: note)
      element("notes.delete.mock-note-2").click()
      let confirmButton = app.buttons["Delete note"].firstMatch
      XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
      confirmButton.click()
      try? openMenu()
      scrollIntoView(element("notes.note.mock-note-1"))
      XCTAssertFalse(element("notes.note.mock-note-2").waitForExistence(timeout: 2))

      attachCheckpoint(
        "destructive-actions",
        identifiers: ["linear.issue.DAY-112", "notes.note.mock-note-1"],
        facts: ["note_deleted=true", "linear_issue_canceled=true"]
      )
    }
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

  func testCreatesLinearAndGitHubIssues() throws {
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
          "# Markdown regression"
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

  func testKeyboardFormattingShortcuts() throws {
    try openMenu()
    element("notes.new").click()

    let editor = noteEditor()
    editor.click()
    editor.typeText("bold italic")

    editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
    editor.typeKey("i", modifierFlags: .command)
    assertValue(of: editor, equals: "bold *italic*")

    editor.typeKey(.leftArrow, modifierFlags: .command)
    editor.typeKey(.rightArrow, modifierFlags: [.option, .shift])
    editor.typeKey("b", modifierFlags: .command)
    assertValue(of: editor, equals: "**bold** *italic*")

    editor.typeKey(.rightArrow, modifierFlags: .command)
    editor.typeKey(.return, modifierFlags: [])
    editor.typeText("list item")
    editor.typeKey("8", modifierFlags: [.command, .shift])
    assertValue(of: editor, equals: "**bold** *italic*\n- list item")

    editor.typeKey(.rightArrow, modifierFlags: .command)
    editor.typeKey(.return, modifierFlags: [])
    editor.typeText("link target")
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
      equals: "**bold** *italic*\n- list item\n- link [target](https://example.com)"
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
    }
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

  private func noteEditor() -> XCUIElement {
    XCTAssertTrue(element("noteEditor.text").waitForExistence(timeout: 5))
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    return editor
  }

  private func revealDestructiveAction(on row: XCUIElement) {
    row.swipeLeft()
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
        editor.typeText(line)
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
