import AppKit
import SwiftUI

/// Button that copies the GitHub device confirmation code to the pasteboard.
struct CopyCodeButton: View {
  /// Code copied when the button is pressed.
  let code: String

  /// Accessibility identifier for the button.
  let accessibilityIdentifier: String

  /// Whether the code was copied moments ago.
  @State private var didCopy = false

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(code, forType: .string)
      didCopy = true
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.5))
        didCopy = false
      }
    } label: {
      Label(code, systemImage: didCopy ? "checkmark" : "doc.on.doc")
        .font(.caption.monospaced())
        .contentTransition(.symbolEffect(.replace))
    }
    .help("Copy code")
    .accessibilityLabel("Copy code \(code)")
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}
