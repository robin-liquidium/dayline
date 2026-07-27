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

  @Test func crashReportStagingUsesActualBytesAndKeepsOlderEligibleReports() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-budget-test-\(UUID().uuidString)", isDirectory: true)
    let stagingRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-staging-test-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: stagingRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))

    let growsAfterDiscovery = root.appendingPathComponent("Dayline-growing.ips")
    let newestEligible = root.appendingPathComponent("Dayline-newest-eligible.ips")
    let exceedsRemainingBudget = root.appendingPathComponent("Dayline-over-budget.ips")
    let oldestEligible = root.appendingPathComponent("Dayline-oldest-eligible.ips")
    try writeCrashHeader(
      bundleID: "de.obermaier.dayline",
      appName: "Dayline",
      to: growsAfterDiscovery,
      paddingBytes: 10
    )
    try writeCrashHeader(
      bundleID: "de.obermaier.dayline",
      appName: "Dayline",
      to: newestEligible,
      paddingBytes: 100
    )
    try writeCrashHeader(
      bundleID: "de.obermaier.dayline",
      appName: "Dayline",
      to: exceedsRemainingBudget,
      paddingBytes: 100
    )
    try writeCrashHeader(
      bundleID: "de.obermaier.dayline",
      appName: "Dayline",
      to: oldestEligible,
      paddingBytes: 10
    )
    for (index, url) in [
      growsAfterDiscovery,
      newestEligible,
      exceedsRemainingBudget,
      oldestEligible,
    ].enumerated() {
      try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(TimeInterval(-index))],
        ofItemAtPath: url.path
      )
    }

    let candidates = DiagnosticsExporter.recentCrashReportCandidates(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now
    )
    let newestBytes = try #require(
      newestEligible.resourceValues(forKeys: [.fileSizeKey]).fileSize
    )
    let oldestBytes = try #require(
      oldestEligible.resourceValues(forKeys: [.fileSizeKey]).fileSize
    )
    let grownData = try FileHandle(forWritingTo: growsAfterDiscovery)
    try grownData.seekToEnd()
    try grownData.write(contentsOf: Data(repeating: 0x20, count: 500))
    try grownData.close()

    let staged = try DiagnosticsExporter.stageCrashReports(
      candidates,
      to: stagingRoot,
      maximumIndividualBytes: newestBytes + 50,
      maximumTotalBytes: newestBytes + oldestBytes
    )

    #expect(
      staged.map(\.lastPathComponent) ==
        [newestEligible, oldestEligible].map(\.lastPathComponent)
    )
    let stagedBytes = try staged.reduce(into: 0) { total, url in
      total += try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }
    #expect(stagedBytes == newestBytes + oldestBytes)
    let stagedNames = try FileManager.default.contentsOfDirectory(atPath: stagingRoot.path)
    #expect(!stagedNames.contains(where: { $0.hasPrefix(".partial-") }))
  }

  @Test func crashReportStagingSkipsTruncatedAndUnreadableCandidates() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-change-test-\(UUID().uuidString)", isDirectory: true)
    let stagingRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-change-staging-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: stagingRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))
    let truncated = root.appendingPathComponent("Dayline-truncated.ips")
    let removed = root.appendingPathComponent("Dayline-removed.ips")
    let stable = root.appendingPathComponent("Dayline-stable.ips")
    for (index, url) in [truncated, removed, stable].enumerated() {
      try writeCrashHeader(
        bundleID: "de.obermaier.dayline",
        appName: "Dayline",
        to: url,
        paddingBytes: 50
      )
      try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(TimeInterval(-index))],
        ofItemAtPath: url.path
      )
    }

    let candidates = DiagnosticsExporter.recentCrashReportCandidates(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now
    )
    try Data().write(to: truncated)
    try FileManager.default.removeItem(at: removed)

    let staged = try DiagnosticsExporter.stageCrashReports(
      candidates,
      to: stagingRoot,
      maximumIndividualBytes: 1024,
      maximumTotalBytes: 1024
    )

    #expect(staged.map(\.lastPathComponent) == [stable.lastPathComponent])
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: stagingRoot.path) ==
        [stable.lastPathComponent]
    )
  }

  @Test func nonPositiveCrashReportCountProducesNoReportsOrStagingDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-count-test-\(UUID().uuidString)", isDirectory: true)
    let stagingRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-count-staging-\(UUID().uuidString)", isDirectory: true)
    let emptyCleanupRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-empty-staging-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: stagingRoot)
      try? FileManager.default.removeItem(at: emptyCleanupRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))
    let report = root.appendingPathComponent("Dayline-current.ips")
    try writeCrashHeader(bundleID: "de.obermaier.dayline", appName: "Dayline", to: report)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: report.path)

    let reports = DiagnosticsExporter.recentCrashReports(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now,
      maximumCount: 0
    )
    let candidates = DiagnosticsExporter.recentCrashReportCandidates(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now
    )
    let staged = try DiagnosticsExporter.stageCrashReports(
      candidates,
      to: stagingRoot,
      maximumCount: -1
    )
    let skipped = try DiagnosticsExporter.stageCrashReports(
      candidates,
      to: emptyCleanupRoot,
      maximumIndividualBytes: 1
    )

    #expect(reports.isEmpty)
    #expect(staged.isEmpty)
    #expect(skipped.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: stagingRoot.path))
    #expect(!FileManager.default.fileExists(atPath: emptyCleanupRoot.path))
  }

  @Test func skippedReportsNeverRemoveAPreexistingCrashDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-owned-test-\(UUID().uuidString)", isDirectory: true)
    let stagingRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-owned-staging-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: stagingRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
    let sentinel = stagingRoot.appendingPathComponent("sentinel.txt")
    try Data("keep me".utf8).write(to: sentinel)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))
    let report = root.appendingPathComponent("Dayline-current.ips")
    try writeCrashHeader(bundleID: "de.obermaier.dayline", appName: "Dayline", to: report)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: report.path)
    let candidates = DiagnosticsExporter.recentCrashReportCandidates(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now
    )

    let staged = try DiagnosticsExporter.stageCrashReports(
      candidates,
      to: stagingRoot,
      maximumIndividualBytes: 1
    )

    #expect(staged.isEmpty)
    #expect(FileManager.default.fileExists(atPath: stagingRoot.path))
    #expect(try Data(contentsOf: sentinel) == Data("keep me".utf8))
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

  @Test func feedbackArchiveTrimsOldestReportsWhileManualExportKeepsAll() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-crash-compression-test-\(UUID().uuidString)", isDirectory: true)
    let logRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-empty-log-test-\(UUID().uuidString)", isDirectory: true)
    let outputRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-archive-size-test-\(UUID().uuidString)", isDirectory: true)
    let feedbackArchive = outputRoot.appendingPathComponent("feedback.zip")
    let manualArchive = outputRoot.appendingPathComponent("manual.zip")
    let feedbackExtraction = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-feedback-size-extract-\(UUID().uuidString)", isDirectory: true)
    let manualExtraction = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayline-manual-size-extract-\(UUID().uuidString)", isDirectory: true)
    defer {
      for url in [
        root,
        logRoot,
        outputRoot,
        feedbackExtraction,
        manualExtraction,
      ] {
        try? FileManager.default.removeItem(at: url)
      }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-27T10:00:00Z"))
    let reports = (0..<3).map { root.appendingPathComponent("Dayline-\($0).ips") }
    for (index, report) in reports.enumerated() {
      try writeIncompressibleCrashReport(
        to: report,
        payloadBytes: 750_000,
        seed: UInt64(index + 1)
      )
      try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(TimeInterval(-index))],
        ofItemAtPath: report.path
      )
    }
    let candidates = DiagnosticsExporter.recentCrashReportCandidates(
      bundleIdentifier: "de.obermaier.dayline",
      displayName: "Dayline",
      roots: [root],
      now: now
    )
    let recorder = DiagnosticLogRecorder(directoryURL: logRoot)

    try DiagnosticsExporter.createArchive(
      at: feedbackArchive,
      purpose: .feedbackAttachment,
      crashReportCandidates: candidates,
      recorder: recorder
    )
    try DiagnosticsExporter.createArchive(
      at: manualArchive,
      purpose: .manualExport,
      crashReportCandidates: candidates,
      recorder: recorder
    )

    let feedbackBytes = try #require(
      feedbackArchive.resourceValues(forKeys: [.fileSizeKey]).fileSize
    )
    let manualBytes = try #require(
      manualArchive.resourceValues(forKeys: [.fileSizeKey]).fileSize
    )
    #expect(feedbackBytes <= FeedbackDiagnosticsContract.maximumArchiveBytes)
    #expect(manualBytes > FeedbackDiagnosticsContract.maximumArchiveBytes)

    try extractArchive(feedbackArchive, to: feedbackExtraction)
    try extractArchive(manualArchive, to: manualExtraction)
    let feedbackNames = try crashReportNames(in: feedbackExtraction)
    let manualNames = try crashReportNames(in: manualExtraction)
    let newestNames = candidates.map(\.sourceURL.lastPathComponent)
    #expect(!feedbackNames.isEmpty)
    #expect(feedbackNames.count < newestNames.count)
    #expect(Set(feedbackNames) == Set(newestNames.prefix(feedbackNames.count)))
    #expect(Set(manualNames) == Set(newestNames))
    #expect(
      Set(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path)) ==
        ["feedback.zip", "manual.zip"]
    )
  }

  private func extractArchive(_ archive: URL, to destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, destination.path]
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
  }

  private func crashReportNames(in extractionRoot: URL) throws -> [String] {
    let crashRoot = extractionRoot
      .appendingPathComponent("Dayline Diagnostics/Crash Reports", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(atPath: crashRoot.path)
  }

  private func writeIncompressibleCrashReport(
    to url: URL,
    payloadBytes: Int,
    seed: UInt64
  ) throws {
    let header = try JSONSerialization.data(withJSONObject: [
      "bundleID": "de.obermaier.dayline",
      "app_name": "Dayline",
    ])
    var payload = Data(count: payloadBytes)
    var state = seed
    payload.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
      for index in buffer.indices {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        buffer[index] = UInt8(32 + (state >> 32) % 95)
      }
    }
    var report = header
    report.append(0x0a)
    report.append(payload)
    try report.write(to: url)
  }

  private func writeCrashHeader(
    bundleID: String,
    appName: String,
    to url: URL,
    paddingBytes: Int = 0
  ) throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "bundleID": bundleID,
      "app_name": appName,
    ])
    var report = data
    report.append(Data("\n{}".utf8))
    report.append(Data(repeating: 0x20, count: paddingBytes))
    try report.write(to: url)
  }
}
