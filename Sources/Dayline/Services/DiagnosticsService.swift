import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Privacy-safe event groups written to unified logging and the local diagnostic ring.
enum DiagnosticCategory: String, Sendable {
  case lifecycle
  case menuBar
  case refresh
  case feedback
}

/// Small, bounded diagnostic breadcrumb log that survives an app crash.
enum DaylineDiagnostics {
  static let recorder = DiagnosticLogRecorder()

  private static let subsystem = Bundle.main.bundleIdentifier ?? "de.obermaier.dayline"
  private static let lifecycleLogger = Logger(subsystem: subsystem, category: DiagnosticCategory.lifecycle.rawValue)
  private static let menuBarLogger = Logger(subsystem: subsystem, category: DiagnosticCategory.menuBar.rawValue)
  private static let refreshLogger = Logger(subsystem: subsystem, category: DiagnosticCategory.refresh.rawValue)
  private static let feedbackLogger = Logger(subsystem: subsystem, category: DiagnosticCategory.feedback.rawValue)

  /// Writes one deliberately non-sensitive breadcrumb to both durable and unified logs.
  static func record(_ message: String, category: DiagnosticCategory) {
    switch category {
    case .lifecycle:
      lifecycleLogger.info("\(message, privacy: .public)")
    case .menuBar:
      menuBarLogger.info("\(message, privacy: .public)")
    case .refresh:
      refreshLogger.info("\(message, privacy: .public)")
    case .feedback:
      feedbackLogger.info("\(message, privacy: .public)")
    }
    recorder.append(message, category: category)
  }
}

/// Thread-safe two-file ring used for a small amount of crash-surviving context.
final class DiagnosticLogRecorder: @unchecked Sendable {
  static let defaultMaximumBytes = 512 * 1024

  let directoryURL: URL
  let currentLogURL: URL
  let previousLogURL: URL

  private let maximumBytes: Int
  private let fileManager: FileManager
  private let lock = NSLock()

  init(
    directoryURL: URL = DiagnosticLogRecorder.defaultDirectoryURL,
    maximumBytes: Int = DiagnosticLogRecorder.defaultMaximumBytes,
    fileManager: FileManager = .default
  ) {
    self.directoryURL = directoryURL
    currentLogURL = directoryURL.appendingPathComponent("dayline.log")
    previousLogURL = directoryURL.appendingPathComponent("dayline.previous.log")
    self.maximumBytes = maximumBytes
    self.fileManager = fileManager
    try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  /// Appends one bounded, single-line event and rotates once when the size cap is reached.
  func append(_ message: String, category: DiagnosticCategory, date: Date = Date()) {
    let cleanMessage = message
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .prefix(500)
    let timestamp = ISO8601DateFormatter().string(from: date)
    guard let data = "\(timestamp) [\(category.rawValue)] \(cleanMessage)\n".data(using: .utf8) else {
      return
    }

    lock.lock()
    defer { lock.unlock() }

    try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    rotateIfNeeded(forAdditionalBytes: data.count)
    if !fileManager.fileExists(atPath: currentLogURL.path) {
      fileManager.createFile(atPath: currentLogURL.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: currentLogURL) else {
      return
    }
    defer { try? handle.close() }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.synchronize()
    } catch {
      return
    }
  }

  /// Copies existing ring files while rotation is paused, preserving newest-first names.
  func copyAvailableLogs(to destinationDirectoryURL: URL) throws {
    lock.lock()
    defer { lock.unlock() }

    try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
    for source in [currentLogURL, previousLogURL] {
      guard fileManager.fileExists(atPath: source.path) else {
        continue
      }
      try fileManager.copyItem(
        at: source,
        to: destinationDirectoryURL.appendingPathComponent(source.lastPathComponent)
      )
    }
  }

  private func rotateIfNeeded(forAdditionalBytes additionalBytes: Int) {
    let currentBytes = (try? currentLogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard currentBytes + additionalBytes > maximumBytes else {
      return
    }
    try? fileManager.removeItem(at: previousLogURL)
    if fileManager.fileExists(atPath: currentLogURL.path) {
      try? fileManager.moveItem(at: currentLogURL, to: previousLogURL)
    }
  }

  private static var defaultDirectoryURL: URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let appFolder = Bundle.main.bundleIdentifier == "build.local.DaylineMock" ? "Dayline Mock" : "Dayline"
    return root
      .appendingPathComponent(appFolder, isDirectory: true)
      .appendingPathComponent("Diagnostics", isDirectory: true)
  }
}

struct CrashReportCandidate: Sendable {
  let sourceURL: URL
  let modifiedAt: Date
  let observedBytes: Int
}

enum FeedbackDiagnosticsContract {
  static let maximumArchiveBytes = 1_500_000
}

/// Builds and saves a user-reviewed ZIP containing bounded logs and recent native crash reports.
struct DiagnosticsExporter {
  private static let maximumCrashReportBytes = 8 * 1024 * 1024
  // Leaves more than 1 MiB for the bounded two-file log ring and README.
  private static let maximumCrashReportTotalBytes = 23 * 1024 * 1024

  /// Presents a standard save panel and returns the saved archive, or nil when cancelled.
  @MainActor
  func export() async throws -> URL? {
    let panel = NSSavePanel()
    panel.title = "Export Dayline Diagnostics"
    panel.prompt = "Export"
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [.zip]
    panel.nameFieldStringValue = Self.defaultArchiveName
    guard panel.runModal() == .OK, let destination = panel.url else {
      return nil
    }

    DaylineDiagnostics.record("Diagnostic export started", category: .feedback)
    let stagedArchiveURL = destination.deletingLastPathComponent()
      .appendingPathComponent(".dayline-diagnostics-\(UUID().uuidString).zip")
    try await Task.detached(priority: .userInitiated) {
      let fileManager = FileManager.default
      defer { try? fileManager.removeItem(at: stagedArchiveURL) }
      try Self.createArchive(at: stagedArchiveURL, purpose: .manualExport)
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: stagedArchiveURL)
      } else {
        try fileManager.moveItem(at: stagedArchiveURL, to: destination)
      }
    }.value
    DaylineDiagnostics.record("Diagnostic export completed", category: .feedback)
    return destination
  }

  /// Creates an archive for an explicitly opted-in feedback submission.
  /// The caller owns and must remove the returned temporary file.
  func createFeedbackAttachment() async throws -> URL {
    try await Task.detached(priority: .userInitiated) {
      let fileManager = FileManager.default
      let archiveURL = fileManager.temporaryDirectory
        .appendingPathComponent("Dayline-Diagnostics-\(UUID().uuidString).zip")
      do {
        try Self.createArchive(at: archiveURL, purpose: .feedbackAttachment)
        return archiveURL
      } catch {
        try? fileManager.removeItem(at: archiveURL)
        throw error
      }
    }.value
  }

  static func createArchive(
    at archiveURL: URL,
    purpose: DiagnosticArchivePurpose,
    crashReportCandidates: [CrashReportCandidate]? = nil,
    recorder: DiagnosticLogRecorder = DaylineDiagnostics.recorder
  ) throws {
    let fileManager = FileManager.default
    let workingRoot = fileManager.temporaryDirectory
      .appendingPathComponent("dayline-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let bundleRoot = workingRoot.appendingPathComponent("Dayline Diagnostics", isDirectory: true)
    defer { try? fileManager.removeItem(at: workingRoot) }

    try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
    try Self.writeSummary(to: bundleRoot, purpose: purpose)
    try Self.copyLogs(to: bundleRoot, recorder: recorder)
    var stagedCrashReports = try Self.copyCrashReports(
      to: bundleRoot,
      candidates: crashReportCandidates
    )
    try Self.replaceZip(from: bundleRoot, at: archiveURL)

    if let maximumArchiveBytes = purpose.maximumArchiveBytes {
      while try Self.fileSize(of: archiveURL) > maximumArchiveBytes {
        guard let oldestReport = stagedCrashReports.popLast() else {
          throw DiagnosticsExportError.archiveTooLarge
        }
        try fileManager.removeItem(at: oldestReport)
        if stagedCrashReports.isEmpty {
          try? fileManager.removeItem(at: oldestReport.deletingLastPathComponent())
        }
        try Self.replaceZip(from: bundleRoot, at: archiveURL)
      }
    }
  }

  private static func writeSummary(to bundleRoot: URL, purpose: DiagnosticArchivePurpose) throws {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let build = info?["CFBundleVersion"] as? String ?? "Unknown"
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion
    let architecture: String
    #if arch(arm64)
      architecture = "Apple Silicon"
    #elseif arch(x86_64)
      architecture = "Intel"
    #else
      architecture = "Unknown"
    #endif

    let summary = """
    Dayline diagnostic export
    Exported: \(ISO8601DateFormatter().string(from: Date()))
    App version: \(version)
    App build: \(build)
    Bundle identifier: \(Bundle.main.bundleIdentifier ?? "Unknown")
    macOS: \(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)
    Architecture: \(architecture)

    \(purpose.disclosure)
    Dayline's own log contains only bounded lifecycle and action breadcrumbs. It intentionally
    excludes account identifiers, calendar and issue contents, notes, URLs, and authentication data.
    Native macOS .ips reports may contain system and device identifiers, loaded-image information,
    and process metadata. Review the archive before sharing it.
    """
    try summary.write(
      to: bundleRoot.appendingPathComponent("README.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  private static func copyLogs(
    to bundleRoot: URL,
    recorder: DiagnosticLogRecorder
  ) throws {
    let logsRoot = bundleRoot.appendingPathComponent("Logs", isDirectory: true)
    try recorder.copyAvailableLogs(to: logsRoot)
  }

  private static func copyCrashReports(
    to bundleRoot: URL,
    candidates suppliedCandidates: [CrashReportCandidate]?
  ) throws -> [URL] {
    let candidates = suppliedCandidates ?? Self.recentCrashReportCandidates(
      bundleIdentifier: Bundle.main.bundleIdentifier,
      displayName: Bundle.main.object(
        forInfoDictionaryKey: "CFBundleDisplayName"
      ) as? String ?? "Dayline"
    )
    guard !candidates.isEmpty else {
      return []
    }
    let crashRoot = bundleRoot.appendingPathComponent("Crash Reports", isDirectory: true)
    return try Self.stageCrashReports(candidates, to: crashRoot)
  }

  /// Discovers matching recent reports in newest-first order without snapshotting them.
  static func recentCrashReports(
    bundleIdentifier: String?,
    displayName: String,
    roots: [URL]? = nil,
    now: Date = Date(),
    maximumCount: Int = 5
  ) -> [URL] {
    guard maximumCount > 0 else {
      return []
    }
    return recentCrashReportCandidates(
      bundleIdentifier: bundleIdentifier,
      displayName: displayName,
      roots: roots,
      now: now
    )
    .prefix(maximumCount)
    .map(\.sourceURL)
  }

  /// Streams stable snapshots into the archive staging directory under both byte budgets.
  @discardableResult
  static func stageCrashReports(
    _ candidates: [CrashReportCandidate],
    to crashRoot: URL,
    maximumIndividualBytes: Int = maximumCrashReportBytes,
    maximumTotalBytes: Int = maximumCrashReportTotalBytes,
    maximumCount: Int = 5
  ) throws -> [URL] {
    guard maximumCount > 0,
          maximumIndividualBytes > 0,
          maximumTotalBytes > 0,
          !candidates.isEmpty else {
      return []
    }

    let fileManager = FileManager.default
    var createdCrashRoot = false
    if !fileManager.fileExists(atPath: crashRoot.path) {
      do {
        try fileManager.createDirectory(at: crashRoot, withIntermediateDirectories: false)
        createdCrashRoot = true
      } catch {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: crashRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
          throw error
        }
      }
    }
    var accepted: [URL] = []
    var acceptedBytes = 0
    for candidate in candidates {
      let remainingBytes = min(
        maximumIndividualBytes,
        maximumTotalBytes - acceptedBytes
      )
      guard remainingBytes > 0 else {
        break
      }

      let destination = crashRoot.appendingPathComponent(candidate.sourceURL.lastPathComponent)
      guard !fileManager.fileExists(atPath: destination.path) else {
        continue
      }
      let partial = crashRoot.appendingPathComponent(".partial-\(UUID().uuidString)")
      guard let copiedBytes = boundedCrashReportSnapshot(
        candidate,
        to: partial,
        maximumBytes: remainingBytes
      ) else {
        try? fileManager.removeItem(at: partial)
        continue
      }

      do {
        try fileManager.moveItem(at: partial, to: destination)
      } catch {
        try? fileManager.removeItem(at: partial)
        throw error
      }
      accepted.append(destination)
      acceptedBytes += copiedBytes
      if accepted.count >= maximumCount {
        break
      }
    }
    if accepted.isEmpty && createdCrashRoot {
      try? fileManager.removeItem(at: crashRoot)
    }
    return accepted
  }

  /// Discovers every matching candidate; staging applies count and byte limits.
  static func recentCrashReportCandidates(
    bundleIdentifier: String?,
    displayName: String,
    roots: [URL]? = nil,
    now: Date = Date()
  ) -> [CrashReportCandidate] {
    let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
    var matches: [CrashReportCandidate] = []

    for root in roots ?? defaultCrashReportRoots {
      guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
      ) else {
        continue
      }
      for case let url as URL in enumerator {
        guard url.pathExtension == "ips",
              let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
              ),
              values.isRegularFile == true,
              let modifiedAt = values.contentModificationDate,
              let fileSize = values.fileSize,
              modifiedAt >= cutoff,
              crashReport(at: url, matchesBundleIdentifier: bundleIdentifier, displayName: displayName) else {
          continue
        }
        matches.append(
          CrashReportCandidate(
            sourceURL: url,
            modifiedAt: modifiedAt,
            observedBytes: fileSize
          )
        )
      }
    }

    return matches.sorted { $0.modifiedAt > $1.modifiedAt }
  }

  /// Copies through a bounded temporary file and accepts only an unchanged complete source.
  private static func boundedCrashReportSnapshot(
    _ candidate: CrashReportCandidate,
    to destination: URL,
    maximumBytes: Int
  ) -> Int? {
    let fileManager = FileManager.default
    guard candidate.observedBytes <= maximumBytes,
          let source = try? FileHandle(forReadingFrom: candidate.sourceURL) else {
      return nil
    }
    defer { try? source.close() }

    guard fileManager.createFile(atPath: destination.path, contents: nil),
          let output = try? FileHandle(forWritingTo: destination) else {
      return nil
    }
    defer { try? output.close() }

    var copiedBytes = 0
    do {
      while true {
        let readLimit = min(64 * 1024, maximumBytes - copiedBytes + 1)
        guard let chunk = try source.read(upToCount: readLimit),
              !chunk.isEmpty else {
          break
        }
        guard copiedBytes + chunk.count <= maximumBytes else {
          return nil
        }
        try output.write(contentsOf: chunk)
        copiedBytes += chunk.count
      }
      try output.synchronize()
      let finalValues = try candidate.sourceURL.resourceValues(
        forKeys: [.contentModificationDateKey, .fileSizeKey]
      )
      guard copiedBytes == candidate.observedBytes,
            finalValues.fileSize == candidate.observedBytes,
            finalValues.contentModificationDate == candidate.modifiedAt else {
        return nil
      }
      return copiedBytes
    } catch {
      return nil
    }
  }

  private static func crashReport(
    at url: URL,
    matchesBundleIdentifier bundleIdentifier: String?,
    displayName: String
  ) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return false
    }
    defer { try? handle.close() }
    guard let headerData = try? handle.read(upToCount: 8 * 1024),
          let header = String(data: headerData, encoding: .utf8)?.split(separator: "\n", maxSplits: 1).first,
          let data = String(header).data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return false
    }
    if let bundleIdentifier {
      return object["bundleID"] as? String == bundleIdentifier
    }
    return object["app_name"] as? String == displayName
  }

  private static func createZip(from directory: URL, at destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = [
      "-c", "-k", "--norsrc", "--noextattr", "--noacl", "--noqtn", "--keepParent",
      directory.path, destination.path,
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw DiagnosticsExportError.archiveFailed
    }
  }

  /// Replaces an existing archive only after a complete new ZIP has been produced.
  private static func replaceZip(from directory: URL, at destination: URL) throws {
    let fileManager = FileManager.default
    let replacement = destination.deletingLastPathComponent()
      .appendingPathComponent(".dayline-zip-\(UUID().uuidString).zip")
    defer { try? fileManager.removeItem(at: replacement) }
    try createZip(from: directory, at: replacement)
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(destination, withItemAt: replacement)
    } else {
      try fileManager.moveItem(at: replacement, to: destination)
    }
  }

  private static func fileSize(of url: URL) throws -> Int {
    guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
      throw DiagnosticsExportError.archiveFailed
    }
    return fileSize
  }

  private static var defaultArchiveName: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    return "Dayline-Diagnostics-\(formatter.string(from: Date())).zip"
  }

  private static var defaultCrashReportRoots: [URL] {
    let reports = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    return [reports, reports.appendingPathComponent("Retired", isDirectory: true)]
  }
}

enum DiagnosticArchivePurpose: Sendable {
  case manualExport
  case feedbackAttachment

  var disclosure: String {
    switch self {
    case .manualExport:
      "This archive was created locally and was not uploaded by Dayline."
    case .feedbackAttachment:
      "This archive was created and uploaded because Include diagnostics was explicitly selected when submitting public feedback. Its public download link expires after 30 days."
    }
  }

  var maximumArchiveBytes: Int? {
    switch self {
    case .manualExport:
      nil
    case .feedbackAttachment:
      FeedbackDiagnosticsContract.maximumArchiveBytes
    }
  }
}

enum DiagnosticsExportError: LocalizedError {
  case archiveFailed
  case archiveTooLarge

  var errorDescription: String? {
    switch self {
    case .archiveFailed:
      "Dayline could not create the diagnostic archive."
    case .archiveTooLarge:
      "Dayline could not reduce the diagnostic archive to the feedback attachment limit."
    }
  }
}
