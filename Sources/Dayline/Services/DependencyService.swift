import Foundation

/// Checks whether Dayline's external CLI dependencies are installed and authenticated.
struct DependencyService {
  /// Shared shell runner used for auth probes.
  var shellClient = ShellClient()

  /// Checks all required dependencies.
  func checkAll() async -> [DependencyStatus] {
    await withTaskGroup(of: DependencyStatus.self) { group in
      for kind in DependencyKind.allCases {
        group.addTask {
          await check(kind)
        }
      }

      var statuses: [DependencyStatus] = []
      for await status in group {
        statuses.append(status)
      }
      return statuses.sorted { $0.kind.id < $1.kind.id }
    }
  }

  /// Checks one dependency without mutating any local CLI auth state.
  func check(_ kind: DependencyKind) async -> DependencyStatus {
    guard FileManager.default.isExecutableFile(atPath: kind.executablePath) else {
      return DependencyStatus(
        kind: kind,
        state: .missing,
        detail: "Expected at \(kind.executablePath)"
      )
    }

    do {
      _ = try await shellClient.checkedRun(kind.executablePath, arguments: kind.authProbeArguments)
      return DependencyStatus(kind: kind, state: .ready, detail: nil)
    } catch {
      return DependencyStatus(
        kind: kind,
        state: .unauthenticated,
        detail: error.localizedDescription.compactLine(limit: 96)
      )
    }
  }
}
