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

/// Shared date field used by editor forms throughout Dayline.
///
/// The button, graphical popover, and optional clear action intentionally live
/// together so every creation flow keeps the same appearance and behavior.
struct CalendarDatePickerField: View {
  @Binding private var selection: Date
  @Binding private var isPresented: Bool

  private let fieldIdentifier: String
  private let calendarIdentifier: String
  private let removeIdentifier: String?
  private let removeHelp: String
  private let onRemove: (() -> Void)?

  init(
    selection: Binding<Date>,
    isPresented: Binding<Bool>,
    fieldIdentifier: String,
    calendarIdentifier: String,
    removeIdentifier: String? = nil,
    removeHelp: String = "Remove date",
    onRemove: (() -> Void)? = nil
  ) {
    _selection = selection
    _isPresented = isPresented
    self.fieldIdentifier = fieldIdentifier
    self.calendarIdentifier = calendarIdentifier
    self.removeIdentifier = removeIdentifier
    self.removeHelp = removeHelp
    self.onRemove = onRemove
  }

  var body: some View {
    HStack(spacing: 6) {
      Button {
        isPresented.toggle()
      } label: {
        Text(selection, format: .dateTime.year().month().day())
      }
      .accessibilityIdentifier(fieldIdentifier)
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        GraphicalDatePicker(selection: $selection)
          .padding(8)
          .accessibilityIdentifier(calendarIdentifier)
      }

      if let onRemove {
        Button {
          isPresented = false
          onRemove()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(removeHelp)
        .accessibilityLabel(removeHelp)
        .accessibilityIdentifier(removeIdentifier ?? "\(fieldIdentifier).remove")
      }
    }
  }
}
