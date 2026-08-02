import SwiftUI

/// Native window for creating an Apple Reminder through EventKit.
struct AppleReminderEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  @State private var draft = AppleReminderCreateDraft()
  @State private var errorMessage: String?
  @State private var isCreating = false

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Title", text: $draft.title, prompt: Text("Reminder title"))
            .accessibilityIdentifier("reminderEditor.title")

          Picker("List", selection: $draft.listID) {
            if !store.writableAppleReminderLists.contains(where: { $0.id == draft.listID }) {
              Text("No writable enabled list selected").tag("")
            }
            ForEach(store.writableAppleReminderLists) { list in
              Text("\(list.title) · \(list.sourceName)").tag(list.id)
            }
          }
          .accessibilityIdentifier("reminderEditor.list")

          if store.writableAppleReminderLists.isEmpty {
            Text("Enable a writable list in Settings → Accounts to create reminders.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("reminderEditor.noWritableList")
          }

          LabeledContent("Priority") {
            ColoredMenuPicker(
              selection: priorityBinding,
              items: AppleReminderPriority.allCases.map { priority in
                ColoredMenuPickerItem(
                  tag: String(priority.rawValue),
                  title: priority.label,
                  symbolName: prioritySystemImage(priority),
                  color: priorityColor(priority)
                )
              }
            )
          }
          .accessibilityIdentifier("reminderEditor.priority")

          dueDateControls
        } header: {
          Label("Reminder", systemImage: "checklist")
        }

        Section {
          TextEditor(text: $draft.notes)
            .font(.body)
            .frame(minHeight: 120)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("reminderEditor.notes")
        } header: {
          Label("Notes", systemImage: "text.alignleft")
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
          .accessibilityIdentifier("reminderEditor.error")
      }

      Divider()

      HStack {
        Toggle("Create more", isOn: createMoreBinding)
          .toggleStyle(.checkbox)
          .help("Keep this window open and start a fresh reminder after creating")
          .accessibilityIdentifier("reminderEditor.createMore")

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("reminderEditor.cancel")

        Button(isCreating ? "Creating..." : "Create") {
          Task { await createReminder() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .accessibilityIdentifier("reminderEditor.create")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(minWidth: 520, idealWidth: 580, minHeight: 470, idealHeight: 540)
    .task {
      if draft.listID.isEmpty {
        resetDraft()
      }
    }
    .onChange(of: store.appleReminderCreationRequestID) { _, _ in
      resetDraft()
    }
    .onChange(of: store.writableAppleReminderLists.map(\.id)) { _, validIDs in
      if !validIDs.contains(draft.listID) {
        draft.listID = validDefaultListID
      }
    }
  }

  @ViewBuilder
  private var dueDateControls: some View {
    if draft.dueDate != nil {
      DatePicker(
        "Due date",
        selection: dueDateBinding,
        displayedComponents: .date
      )
      .accessibilityIdentifier("reminderEditor.dueDate")

      Toggle("Include time", isOn: dueTimeEnabledBinding)
        .accessibilityIdentifier("reminderEditor.dueTimeEnabled")

      if draft.dueDateIncludesTime {
        DatePicker(
          "Due time",
          selection: dueDateBinding,
          displayedComponents: .hourAndMinute
        )
        .accessibilityIdentifier("reminderEditor.dueTime")
      }

      Button(role: .destructive) {
        draft.dueDate = nil
        draft.dueDateIncludesTime = false
      } label: {
        Label("Remove due date", systemImage: "xmark.circle")
      }
      .accessibilityIdentifier("reminderEditor.dueDate.remove")
    } else {
      Button {
        draft.dueDate = Calendar.current.startOfDay(for: Date())
      } label: {
        Label("Add due date", systemImage: "calendar")
      }
      .accessibilityIdentifier("reminderEditor.dueDate.add")
    }
  }

  private var canCreate: Bool {
    !isCreating
      && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && store.writableAppleReminderLists.contains { $0.id == draft.listID }
  }

  private var createMoreBinding: Binding<Bool> {
    Binding(
      get: { store.issueCreateMoreEnabled },
      set: { store.setIssueCreateMoreEnabled($0) }
    )
  }

  private var priorityBinding: Binding<String> {
    Binding(
      get: { String(draft.priority.rawValue) },
      set: { draft.priority = AppleReminderPriority(eventKitValue: Int($0) ?? 0) }
    )
  }

  private var dueDateBinding: Binding<Date> {
    Binding(
      get: { draft.dueDate ?? Date() },
      set: { draft.dueDate = $0 }
    )
  }

  private var dueTimeEnabledBinding: Binding<Bool> {
    Binding(
      get: { draft.dueDateIncludesTime },
      set: { includesTime in
        draft.dueDateIncludesTime = includesTime
        guard includesTime, let dueDate = draft.dueDate else { return }
        let now = Date()
        let day = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: now)
        draft.dueDate = Calendar.current.date(from: DateComponents(
          year: day.year,
          month: day.month,
          day: day.day,
          hour: time.hour,
          minute: time.minute
        )) ?? dueDate
      }
    )
  }

  private func createReminder() async {
    guard canCreate else { return }
    isCreating = true
    errorMessage = nil
    do {
      try await store.createAppleReminder(draft: draft)
      if store.issueCreateMoreEnabled {
        resetDraft()
      } else {
        dismiss()
      }
    } catch {
      errorMessage = error.localizedDescription.compactLine(limit: 160)
    }
    isCreating = false
  }

  private func resetDraft() {
    draft = AppleReminderCreateDraft(
      title: "",
      notes: "",
      listID: validDefaultListID,
      priority: store.appleReminderCreateDefaultPriority,
      dueDate: nil,
      dueDateIncludesTime: false
    )
    errorMessage = nil
  }

  private var validDefaultListID: String {
    if store.writableAppleReminderLists.contains(where: {
      $0.id == store.appleReminderCreateDefaultListID
    }) {
      return store.appleReminderCreateDefaultListID
    }
    return store.writableAppleReminderLists.first?.id ?? ""
  }

  private func prioritySystemImage(_ priority: AppleReminderPriority) -> String {
    switch priority {
    case .high: "exclamationmark.circle.fill"
    case .medium: "equal.circle.fill"
    case .low: "arrow.down.circle.fill"
    case .none: "ellipsis.circle"
    }
  }

  private func priorityColor(_ priority: AppleReminderPriority) -> Color {
    switch priority {
    case .high: .orange
    case .medium: .yellow
    case .low, .none: .secondary
    }
  }
}
