import AppKit
import Testing
@testable import Dayline

struct IssueClickActionTests {
  @Test(arguments: IssueClickAction.allCases, IssueClickModifier.allCases)
  func clickUsesTheConfiguredActionAndModifier(action: IssueClickAction, modifier: IssueClickModifier) {
    #expect(action.resolved(modifiers: [], alternateModifier: modifier) == action)
    #expect(action.resolved(modifiers: modifier.flags, alternateModifier: modifier) == action.alternate)
    #expect(action.resolved(modifiers: [modifier.flags, .capsLock], alternateModifier: modifier) == action.alternate)
    for other in IssueClickModifier.allCases where other != modifier {
      #expect(action.resolved(modifiers: other.flags, alternateModifier: modifier) == action)
    }
  }

  @Test @MainActor func detailsRemainAvailableWithoutABrowserURLAndCloseOtherPickers() throws {
    let store = StatusStore(mockData: MockData.make())
    let originalAction = store.issueClickAction
    defer { store.issueClickAction = originalAction }
    let issue = try #require(store.issues.first)
    store.issueClickAction = .openInBrowser
    store.setHoveredIssue(.linear(issue.id))
    #expect(store.presentStatusPickerForHoveredIssue())

    store.activateIssue(.linear(issue.id), url: nil)

    #expect(store.previewTarget == .issue(.linear(issue.id)))
    #expect(store.statusPickerTarget == nil)
    store.activateIssue(.linear(issue.id), url: nil)
    #expect(store.previewTarget == nil)
  }

  @Test @MainActor func metadataChangesPreserveIssueDescriptions() async throws {
    let mock = MockData.make()
    let store = StatusStore(mockData: mock)
    let issue = try #require(store.issues.first)
    let description = try #require(issue.body)
    let state = try #require(issue.workflowStates.first { $0.type == "started" })
    await store.changeIssueStatus(issueID: issue.id, state: state)
    #expect(store.issues.first { $0.id == issue.id }?.body == description)
    #expect(issue.replacing(labels: []).body == description)

    let githubIssue = try #require(mock.githubIssues.first)
    #expect(githubIssue.body != nil)
    #expect(githubIssue.replacing(labels: [], assignees: []).body == githubIssue.body)
  }
}
