import AppKit
import SwiftUI

/// Native macOS calendar picker without the stock bezel and background chrome,
/// so it blends into popovers like the system calendar does.
struct GraphicalDatePicker: NSViewRepresentable {
  @Binding var selection: Date

  /// Builds the underlying borderless, background-less AppKit date picker.
  func makeNSView(context: Context) -> NSDatePicker {
    let picker = NSDatePicker()
    picker.datePickerStyle = .clockAndCalendar
    picker.datePickerElements = [.yearMonthDay]
    picker.datePickerMode = .single
    picker.isBordered = false
    picker.drawsBackground = false
    picker.backgroundColor = .clear
    picker.focusRingType = .none
    picker.dateValue = selection
    picker.target = context.coordinator
    picker.action = #selector(Coordinator.dateChanged(_:))
    return picker
  }

  /// Pushes external selection changes into the picker.
  func updateNSView(_ picker: NSDatePicker, context: Context) {
    if picker.dateValue != selection {
      picker.dateValue = selection
    }
  }

  /// Creates the action coordinator bridging picker changes back into SwiftUI.
  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  /// Receives picker target-action callbacks.
  final class Coordinator: NSObject {
    @Binding var selection: Date

    init(selection: Binding<Date>) {
      _selection = selection
    }

    @objc func dateChanged(_ sender: NSDatePicker) {
      selection = sender.dateValue
    }
  }
}
