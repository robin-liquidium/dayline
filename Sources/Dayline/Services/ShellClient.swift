import Foundation

/// Captures a completed command's output streams.
struct CommandResult {
  /// Standard output decoded as UTF-8 text.
  let stdout: String

  /// Standard error decoded as UTF-8 text.
  let stderr: String

  /// Integer process exit status.
  let status: Int32
}

/// Errors produced by command execution.
enum ShellClientError: LocalizedError {
  case failedToLaunch(String)
  case nonZeroExit(command: String, status: Int32, stderr: String)

  /// Human-readable error text suitable for compact UI states.
  var errorDescription: String? {
    switch self {
    case .failedToLaunch(let command):
      return "Could not launch \(command)."
    case .nonZeroExit(let command, let status, let stderr):
      let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return detail.isEmpty ? "\(command) exited with status \(status)." : detail
    }
  }
}

/// Runs small CLI commands asynchronously without blocking SwiftUI.
actor ShellClient {
  /// Search path supplied to GUI-launched CLI wrappers that use `/usr/bin/env`.
  private static let fallbackExecutableSearchPath = [
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin"
  ]

  /// Runs a command and returns captured output after the process exits.
  func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()

      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.environment = Self.processEnvironment()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      process.terminationHandler = { finishedProcess in
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        continuation.resume(returning: CommandResult(stdout: stdout, stderr: stderr, status: finishedProcess.terminationStatus))
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: ShellClientError.failedToLaunch(executable))
      }
    }
  }

  /// Builds a stable process environment for apps launched outside a login shell.
  private static func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let inheritedPath = environment["PATH"]?
      .split(separator: ":")
      .map(String.init) ?? []
    var seenPaths: Set<String> = []
    let mergedPath = (inheritedPath + fallbackExecutableSearchPath).filter { path in
      seenPaths.insert(path).inserted
    }
    environment["PATH"] = mergedPath.joined(separator: ":")
    return environment
  }

  /// Runs a command and throws when the exit status is not zero.
  func checkedRun(_ executable: String, arguments: [String]) async throws -> CommandResult {
    let result = try await run(executable, arguments: arguments)
    guard result.status == 0 else {
      throw ShellClientError.nonZeroExit(command: executable, status: result.status, stderr: result.stderr)
    }
    return result
  }
}
