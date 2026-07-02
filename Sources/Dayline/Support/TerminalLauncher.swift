import Foundation

/// Opens setup commands in Terminal so users can inspect and approve CLI changes.
enum TerminalLauncher {
  /// Opens a new Terminal tab with a command ready to run.
  static func run(_ command: String) {
    let script = """
    tell application "Terminal"
      activate
      do script "\(appleScriptEscaped(command))"
    end tell
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try? process.run()
  }

  /// Escapes a shell command for embedding inside an AppleScript string literal.
  private static func appleScriptEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
