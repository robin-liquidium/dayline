import SwiftUI

/// Native window for creating an event in Apple Calendar through EventKit.
struct AppleCalendarEventEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  @State private var draft = AppleCalendarEventCreateDraft()
  @State private var errorMessage: String?
  @State private var isCreating = false
  @State private var isStartDatePickerPresented = false
  @State private var isEndDatePickerPresented = false

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Title", text: $draft.title, prompt: Text("Event title"))
            .accessibilityIdentifier("calendarEventEditor.title")

          Picker("Calendar", selection: $draft.calendarID) {
            if !store.writableAppleCalendars.contains(where: { $0.id == draft.calendarID }) {
              Text("No writable enabled calendar selected").tag("")
            }
            ForEach(store.writableAppleCalendars) { calendar in
              Text("\(calendar.title) · \(calendar.sourceName)").tag(calendar.id)
            }
          }
          .accessibilityIdentifier("calendarEventEditor.calendar")

          if store.writableAppleCalendars.isEmpty {
            Text("Enable a writable Apple calendar in Settings → Accounts to create events.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("calendarEventEditor.noWritableCalendar")
          }

          Toggle("All-day event", isOn: $draft.isAllDay)
            .accessibilityIdentifier("calendarEventEditor.allDay")

          eventDateRow(
            "Starts",
            selection: $draft.startDate,
            isPresented: $isStartDatePickerPresented,
            identifier: "calendarEventEditor.start"
          )

          eventDateRow(
            "Ends",
            selection: $draft.endDate,
            isPresented: $isEndDatePickerPresented,
            identifier: "calendarEventEditor.end"
          )

          if draft.isAllDay {
            Text("The end date is inclusive.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } header: {
          Label("Event", systemImage: "calendar.badge.plus")
        }
      }
      .formStyle(.grouped)

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 20)
          .padding(.bottom, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("calendarEventEditor.error")
      }

      Divider()

      HStack {
        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("calendarEventEditor.cancel")

        Button(isCreating ? "Creating..." : "Create") {
          guard canCreate else { return }
          isCreating = true
          Task { await createEvent() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .accessibilityIdentifier("calendarEventEditor.create")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(minWidth: 500, idealWidth: 560, minHeight: 380, idealHeight: 440)
    .task {
      resetDraft()
    }
    .onChange(of: store.appleCalendarEventCreationRequestID) { _, _ in
      resetDraft()
    }
    .onChange(of: store.writableAppleCalendars.map(\.id)) { _, validIDs in
      if !validIDs.contains(draft.calendarID) {
        draft.calendarID = store.defaultAppleCalendarEventCalendarID
      }
    }
    .onChange(of: draft.startDate) { oldStart, newStart in
      repairEndDate(previousStart: oldStart, newStart: newStart)
    }
    .onChange(of: draft.isAllDay) { _, isAllDay in
      if isAllDay {
        draft.startDate = Calendar.current.startOfDay(for: draft.startDate)
        draft.endDate = max(
          Calendar.current.startOfDay(for: draft.endDate),
          draft.startDate
        )
      } else if draft.endDate <= draft.startDate {
        draft.endDate = draft.startDate.addingTimeInterval(30 * 60)
      }
    }
  }

  private var canCreate: Bool {
    !isCreating
      && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && store.writableAppleCalendars.contains { $0.id == draft.calendarID }
      && validDateRange
  }

  /// Shared date field plus a compact time control for timed events.
  private func eventDateRow(
    _ title: String,
    selection: Binding<Date>,
    isPresented: Binding<Bool>,
    identifier: String
  ) -> some View {
    LabeledContent(title) {
      HStack(spacing: 8) {
        CalendarDatePickerField(
          selection: selection,
          isPresented: isPresented,
          fieldIdentifier: "\(identifier).date",
          calendarIdentifier: "\(identifier).calendar"
        )

        if !draft.isAllDay {
          DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .accessibilityLabel("\(title) time")
            .accessibilityIdentifier("\(identifier).time")
        }
      }
    }
  }

  private var validDateRange: Bool {
    if draft.isAllDay {
      return Calendar.current.startOfDay(for: draft.endDate)
        >= Calendar.current.startOfDay(for: draft.startDate)
    }
    return draft.endDate > draft.startDate
  }

  private func createEvent() async {
    defer { isCreating = false }
    errorMessage = nil
    do {
      try await store.createAppleCalendarEvent(draft: draft)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription.compactLine(limit: 160)
    }
  }

  private func resetDraft() {
    let calendar = Calendar.current
    let now = Date()
    let minute = calendar.component(.minute, from: now)
    let minutesToNextHalfHour = minute < 30 ? 30 - minute : 60 - minute
    let start = calendar.date(byAdding: .minute, value: minutesToNextHalfHour, to: now) ?? now
    let roundedStart = calendar.date(bySetting: .second, value: 0, of: start) ?? start
    draft = AppleCalendarEventCreateDraft(
      title: "",
      calendarID: store.defaultAppleCalendarEventCalendarID,
      startDate: roundedStart,
      endDate: roundedStart.addingTimeInterval(30 * 60),
      isAllDay: false
    )
    errorMessage = nil
    isStartDatePickerPresented = false
    isEndDatePickerPresented = false
  }

  private func repairEndDate(previousStart: Date, newStart: Date) {
    if draft.isAllDay {
      let startDay = Calendar.current.startOfDay(for: newStart)
      if Calendar.current.startOfDay(for: draft.endDate) < startDay {
        draft.endDate = startDay
      }
      return
    }

    let previousDuration = draft.endDate.timeIntervalSince(previousStart)
    if previousDuration > 0 {
      draft.endDate = newStart.addingTimeInterval(previousDuration)
    } else if draft.endDate <= newStart {
      draft.endDate = newStart.addingTimeInterval(30 * 60)
    }
  }
}
