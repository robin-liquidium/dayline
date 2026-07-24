import SwiftUI

/// Calendar menu, menu bar title, and meeting alert settings.
struct CalendarSettingsTab: View {
  @EnvironmentObject private var store: StatusStore

  /// Supported pre-meeting menu bar title lead choices in minutes.
  private let menuBarLeadTimeOptions = [0, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

  /// Supported post-start menu bar title grace choices in minutes.
  private let menuBarPostStartGraceOptions = [0, 1, 2, 5, 10, 15, 20, 25, 30]

  var body: some View {
    Form {
      Section {
        Picker("Show title before", selection: menuBarLeadTimeBinding) {
          ForEach(menuBarLeadTimePickerOptions, id: \.self) { minutes in
            Text(minutesLabel(for: minutes)).tag(minutes)
          }
        }
        .accessibilityIdentifier("settings.menuBarEventLeadTime")

        Picker("Show title after", selection: menuBarPostStartGraceBinding) {
          ForEach(menuBarPostStartGracePickerOptions, id: \.self) { minutes in
            Text(minutesLabel(for: minutes)).tag(minutes)
          }
        }
        .accessibilityIdentifier("settings.menuBarEventPostStartGrace")
      } header: {
        Label("Menu Bar Title", systemImage: "menubar.rectangle")
      }

      Section {
        Toggle("Show calendar in menu", isOn: showsCalendarSectionBinding)
          .accessibilityIdentifier("settings.showsCalendarSection")

        Toggle("Show calendar names", isOn: showsCalendarSourceNamesBinding)
          .accessibilityIdentifier("settings.showsCalendarSourceNames")
      } header: {
        Label("Menu", systemImage: "list.bullet")
      }

      Section {
        Toggle("Full-screen meeting alerts", isOn: meetingAlertEnabledBinding)
          .accessibilityIdentifier("settings.meetingAlertEnabled")

        Picker("Show alert", selection: meetingAlertLeadBinding) {
          ForEach(meetingAlertLeadPickerOptions, id: \.self) { minutes in
            Text(minutes == 0 ? "When the meeting starts" : "\(minutes) min before").tag(minutes)
          }
        }
        .disabled(!store.meetingAlertEnabled)
        .accessibilityIdentifier("settings.meetingAlertLead")
      } header: {
        Label("Meeting Alerts", systemImage: "bell.badge")
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Binding that forwards menu bar pre-meeting window changes to the store.
  private var menuBarLeadTimeBinding: Binding<Int> {
    Binding(
      get: { store.menuBarEventLeadTimeMinutes },
      set: { store.setMenuBarEventLeadTime(minutes: $0) }
    )
  }

  /// Binding that forwards menu bar post-start window changes to the store.
  private var menuBarPostStartGraceBinding: Binding<Int> {
    Binding(
      get: { store.menuBarEventPostStartGraceMinutes },
      set: { store.setMenuBarEventPostStartGrace(minutes: $0) }
    )
  }

  /// Lead time choices plus any existing custom stored value.
  private var menuBarLeadTimePickerOptions: [Int] {
    Array(Set(menuBarLeadTimeOptions + [store.menuBarEventLeadTimeMinutes])).sorted()
  }

  /// Post-start choices plus any existing custom stored value.
  private var menuBarPostStartGracePickerOptions: [Int] {
    Array(Set(menuBarPostStartGraceOptions + [store.menuBarEventPostStartGraceMinutes])).sorted()
  }

  /// Binding that persists whether the calendar section appears in the menu.
  private var showsCalendarSectionBinding: Binding<Bool> {
    Binding(
      get: { store.showsCalendarSection },
      set: { store.setShowsCalendarSection($0) }
    )
  }

  /// Binding that persists whether event rows show source calendar names.
  private var showsCalendarSourceNamesBinding: Binding<Bool> {
    Binding(
      get: { store.showsCalendarSourceNames },
      set: { store.setShowsCalendarSourceNames($0) }
    )
  }

  /// Binding that persists whether full-screen meeting alerts are enabled.
  private var meetingAlertEnabledBinding: Binding<Bool> {
    Binding(
      get: { store.meetingAlertEnabled },
      set: { store.setMeetingAlertEnabled($0) }
    )
  }

  /// Binding that persists how early the meeting alert may appear.
  private var meetingAlertLeadBinding: Binding<Int> {
    Binding(
      get: { store.meetingAlertLeadMinutes },
      set: { store.setMeetingAlertLead(minutes: $0) }
    )
  }

  /// Alert lead choices plus any existing custom stored value.
  private var meetingAlertLeadPickerOptions: [Int] {
    Array(Set([0, 1, 2, 5, 10, 15, 30] + [store.meetingAlertLeadMinutes])).sorted()
  }

  /// Returns a compact label for a minute-based menu bar title setting.
  private func minutesLabel(for minutes: Int) -> String {
    minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}
