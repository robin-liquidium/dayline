import Foundation
import Testing
@testable import Dayline

struct DiagnosticsServiceTests {
  @Test func diagnosticLogRotatesAndKeepsTheNewestEntry() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-log-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = DiagnosticLogRecorder(directoryURL: root, maximumBytes: 110)
    let date = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))

    recorder.append(String(repeating: "a", count: 70), category: .lifecycle, date: date)
    recorder.append("newest", category: .menuBar, date: date.addingTimeInterval(1))

    #expect(FileManager.default.fileExists(atPath: recorder.previousLogURL.path))
    let current = try String(contentsOf: recorder.currentLogURL, encoding: .utf8)
    let previous = try String(contentsOf: recorder.previousLogURL, encoding: .utf8)
    #expect(current.contains("[menuBar] newest"))
    #expect(previous.contains("[lifecycle]"))
  }

  @Test func diagnosticLogCopiesTheStableRingNames() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-log-copy-test-\(UUID().uuidString)", isDirectory: true)
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-log-copy-destination-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: destination)
    }
    let recorder = DiagnosticLogRecorder(directoryURL: root, maximumBytes: 110)
    let date = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))
    recorder.append(String(repeating: "a", count: 70), category: .lifecycle, date: date)
    recorder.append("newest", category: .menuBar, date: date.addingTimeInterval(1))

    try recorder.copyAvailableLogs(to: destination)

    let current = try String(
      contentsOf: destination.appendingPathComponent("dayline.log"),
      encoding: .utf8
    )
    let previous = try String(
      contentsOf: destination.appendingPathComponent("dayline.previous.log"),
      encoding: .utf8
    )
    #expect(current.contains("[menuBar] newest"))
    #expect(previous.contains("[lifecycle]"))
  }

  @Test func crashReportDiscoveryUsesBundleIdentifierAndRecency() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))

    let matching = root.appendingPathComponent("Dayline-current.ips")
    let other = root.appendingPathComponent("Other-current.ips")
    let sameNameWrongBundle = root.appendingPathComponent("Dayline-wrong-bundle.ips")
    let old = root.appendingPathComponent("Dayline-old.ips")
    try writeCrashHeader(bundleID: "de.obermaier.dayline", appName: "Dayline", to: matching)
    try writeCrashHeader(bundleID: "example.other", appName: "Other", to: other)
    try writeCrashHeader(bundleID: "example.other", appName: "Dayline", to: sameNameWrongBundle)
    try writeCrashHeader(bundleID: "de.obermaier.dayline", appName: "Dayline", to: old)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: matching.path)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: other.path)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: sameNameWrongBundle.path)
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-15 * 24 * 60 * 60)],
      ofItemAtPath: old.path
    )

    let reports = DiagnosticsExporter.recentCrashReports(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now
    )

    #expect(reports.map { $0.resolvingSymlinksInPath() } == [matching.resolvingSymlinksInPath()])
  }

  @Test func feedbackAttachmentDisclosesThePublicUpload() async throws {
    let archive = try await DiagnosticsExporter().createFeedbackAttachment()
    let extractionRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-feedback-archive-test-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: archive)
      try? FileManager.default.removeItem(at: extractionRoot)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, extractionRoot.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let readme = try String(
      contentsOf: extractionRoot.appendingPathComponent("Dayline Diagnostics/README.txt"),
      encoding: .utf8
    )
    #expect(readme.contains("Include diagnostics was explicitly selected"))
    #expect(readme.contains("public download link expires after 30 days"))
  }

  private func writeCrashHeader(bundleID: String, appName: String, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "bundleID": bundleID,
      "app_name": appName,
    ])
    var report = data
    report.append(Data("\n{}".utf8))
    try report.write(to: url)
  }
}
