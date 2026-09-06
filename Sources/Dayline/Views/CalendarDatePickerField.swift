import SwiftUI

/// Shared date field used by editor forms throughout Dayline.
///
/// The button, graphical popover, and optional clear action intentionally live
/// together so every creation flow keeps the same appearance and behavior.
struct CalendarDatePickerField: View {
  @Binding var selection: Date
  @Binding var isPresented: Bool

  let fieldIdentifier: String
  let calendarIdentifier: String
  var removeIdentifier: String? = nil
  var removeHelp: String = "Remove date"
  var onRemove: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 6) {
      Button {
        isPresented.toggle()
      } label: {
        Text(selection, format: .dateTime.year().month().day())
      }
      .accessibilityIdentifier(fieldIdentifier)
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        DatePicker("Date", selection: $selection, displayedComponents: .date)
          .datePickerStyle(.graphical)
          .labelsHidden()
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
