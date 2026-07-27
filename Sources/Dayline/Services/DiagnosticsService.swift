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

  private static func createArchive(at archiveURL: URL, purpose: DiagnosticArchivePurpose) throws {
    let fileManager = FileManager.default
    let workingRoot = fileManager.temporaryDirectory
      .appendingPathComponent("dayline-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let bundleRoot = workingRoot.appendingPathComponent("Dayline Diagnostics", isDirectory: true)
    defer { try? fileManager.removeItem(at: workingRoot) }

    try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
    try Self.writeSummary(to: bundleRoot, purpose: purpose)
    try Self.copyLogs(to: bundleRoot)
    try Self.copyCrashReports(to: bundleRoot)
    try Self.createZip(from: bundleRoot, at: archiveURL)
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

  private static func copyLogs(to bundleRoot: URL) throws {
    let logsRoot = bundleRoot.appendingPathComponent("Logs", isDirectory: true)
    try DaylineDiagnostics.recorder.copyAvailableLogs(to: logsRoot)
  }

  private static func copyCrashReports(to bundleRoot: URL) throws {
    let reports = Self.recentCrashReports(
      bundleIdentifier: Bundle.main.bundleIdentifier,
      displayName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Dayline"
    )
    guard !reports.isEmpty else {
      return
    }
    let crashRoot = bundleRoot.appendingPathComponent("Crash Reports", isDirectory: true)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: crashRoot, withIntermediateDirectories: true)
    for source in reports {
      try fileManager.copyItem(at: source, to: crashRoot.appendingPathComponent(source.lastPathComponent))
    }
  }

  /// Finds up to five recent reports belonging to this exact app bundle.
  static func recentCrashReports(
    bundleIdentifier: String?,
    displayName: String,
    roots: [URL]? = nil,
    now: Date = Date(),
    maximumIndividualBytes: Int = maximumCrashReportBytes,
    maximumTotalBytes: Int = maximumCrashReportTotalBytes,
    maximumCount: Int = 5
  ) -> [URL] {
    let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
    var matches: [(url: URL, date: Date, size: Int)] = []

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
        matches.append((url, modifiedAt, fileSize))
      }
    }

    var selected: [URL] = []
    var selectedBytes = 0
    for match in matches.sorted(by: { $0.date > $1.date }) {
      guard match.size <= maximumIndividualBytes,
            selectedBytes + match.size <= maximumTotalBytes else {
        continue
      }
      selected.append(match.url)
      selectedBytes += match.size
      if selected.count == maximumCount {
        break
      }
    }
    return selected
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

private enum DiagnosticArchivePurpose: Sendable {
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
}

enum DiagnosticsExportError: LocalizedError {
  case archiveFailed

  var errorDescription: String? {
    "Dayline could not create the diagnostic archive."
  }
}
