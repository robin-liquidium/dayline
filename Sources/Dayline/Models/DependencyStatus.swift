import Foundation

/// External CLI dependency that Dayline needs for a data source.
enum DependencyKind: CaseIterable, Identifiable {
  /// Google Workspace CLI used for Calendar.
  case googleWorkspace

  /// Linear CLI used for issues.
  case linear

  /// Stable identity.
  var id: String {
    switch self {
    case .googleWorkspace:
      "gws"
    case .linear:
      "linear"
    }
  }

  /// Human-readable dependency name.
  var title: String {
    switch self {
    case .googleWorkspace:
      "Google Workspace CLI"
    case .linear:
      "Linear CLI"
    }
  }

  /// Short name used in compact setup rows.
  var shortTitle: String {
    switch self {
    case .googleWorkspace:
      "gws"
    case .linear:
      "linear"
    }
  }

  /// Configured executable path.
  var executablePath: String {
    switch self {
    case .googleWorkspace:
      CLIPaths.gws
    case .linear:
      CLIPaths.linear
    }
  }

  /// Command to open in Terminal for installation.
  var installCommand: String {
    switch self {
    case .googleWorkspace:
      ProcessInfo.processInfo.environment["DAYLINE_GWS_INSTALL_COMMAND"] ?? "brew install googleworkspace-cli"
    case .linear:
      ProcessInfo.processInfo.environment["DAYLINE_LINEAR_INSTALL_COMMAND"] ?? "npm install -g @schpet/linear-cli"
    }
  }

  /// Command to open in Terminal for authentication.
  var authCommand: String {
    "\(Self.shellQuoted(executablePath)) \(authArguments.joined(separator: " "))"
  }

  /// Non-mutating arguments used to check authentication.
  var authProbeArguments: [String] {
    switch self {
    case .googleWorkspace:
      ["auth", "status"]
    case .linear:
      ["auth", "whoami"]
    }
  }

  /// Mutating or interactive auth arguments for the user's Terminal.
  private var authArguments: [String] {
    switch self {
    case .googleWorkspace:
      ["auth", "login"]
    case .linear:
      ["auth", "login"]
    }
  }

  /// Safely quotes a shell argument for display in a Terminal command.
  private static func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}

/// Current setup state for one CLI dependency.
enum DependencyState: Equatable {
  /// The app has not checked this dependency yet.
  case checking

  /// The executable does not exist at the configured path.
  case missing

  /// The executable exists, but auth probing failed.
  case unauthenticated

  /// The executable exists and auth probing succeeded.
  case ready
}

/// Display-ready dependency status for the menu.
struct DependencyStatus: Identifiable, Equatable {
  /// Dependency being checked.
  let kind: DependencyKind

  /// Current setup state.
  let state: DependencyState

  /// Optional detail from the executable or preflight checker.
  let detail: String?

  /// Stable identity.
  var id: DependencyKind.ID {
    kind.id
  }

  /// Whether this dependency can be used for refreshes.
  var isReady: Bool {
    state == .ready
  }

  /// Human-readable status title.
  var title: String {
    switch state {
    case .checking:
      "Checking \(kind.shortTitle)"
    case .missing:
      "\(kind.shortTitle) is not installed"
    case .unauthenticated:
      "\(kind.shortTitle) is not authenticated"
    case .ready:
      "\(kind.shortTitle) is ready"
    }
  }

  /// Initial status list shown before the first async preflight completes.
  static var checkingAll: [DependencyStatus] {
    DependencyKind.allCases.map {
      DependencyStatus(kind: $0, state: .checking, detail: nil)
    }
  }
}
