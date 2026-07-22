import Foundation
import Testing
@testable import Dayline

@Suite("Linear team estimate options")
struct LinearTeamEstimateOptionTests {
  private func team(
    type: String,
    allowZero: Bool = false,
    extended: Bool = false
  ) -> LinearTeamOption {
    LinearTeamOption(
      id: "team",
      key: "DAY",
      name: "Dayline",
      states: [],
      issueEstimationType: type,
      issueEstimationAllowZero: allowZero,
      issueEstimationExtended: extended
    )
  }

  @Test("Estimation scales match Linear's documented ranges")
  func scaleRanges() {
    #expect(team(type: "exponential").estimateOptions.map(\.value) == [1, 2, 4, 8, 16])
    #expect(team(type: "fibonacci").estimateOptions.map(\.value) == [1, 2, 3, 5, 8])
    #expect(team(type: "linear").estimateOptions.map(\.value) == [1, 2, 3, 4, 5])
    #expect(team(type: "tShirt").estimateOptions.map(\.value) == [1, 2, 3, 5, 8])
  }

  @Test("Extended scales add two larger values")
  func extendedScales() {
    #expect(team(type: "exponential", extended: true).estimateOptions.map(\.value) == [1, 2, 4, 8, 16, 32, 64])
    #expect(team(type: "fibonacci", extended: true).estimateOptions.map(\.value) == [1, 2, 3, 5, 8, 13, 21])
    #expect(team(type: "linear", extended: true).estimateOptions.map(\.value) == [1, 2, 3, 4, 5, 6, 7])
    #expect(team(type: "tShirt", extended: true).estimateOptions.map(\.label) == ["XS", "S", "M", "L", "XL", "XXL", "XXXL"])
  }

  @Test("T-shirt scales use size labels on fibonacci values")
  func tShirtLabels() {
    let options = team(type: "tShirt").estimateOptions
    #expect(options.map(\.label) == ["XS", "S", "M", "L", "XL"])
  }

  @Test("Zero estimates are prepended when allowed")
  func zeroEstimates() {
    #expect(team(type: "linear", allowZero: true).estimateOptions.map(\.value) == [0, 1, 2, 3, 4, 5])
  }

  @Test("Teams without estimation offer no estimate options")
  func estimatesDisabled() {
    #expect(team(type: "notUsed").estimateOptions.isEmpty)
  }
}
