import SwiftUI

/// Zen full-screen alert shown when a meeting starts.
struct MeetingAlertView: View {
  let event: CalendarEventItem
  let onJoin: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DaylineWordmark(height: 34)
        .opacity(0.7)

      Spacer()

      TimelineView(.periodic(from: .now, by: 15)) { _ in
        Text(startLabel)
          .font(.system(size: 20, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.bottom, 16)
      }

      Text(event.title)
        .font(.system(size: 60, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 80)
        .padding(.bottom, 12)

      Text(DisplayFormatters.eventTimeRange(start: event.startDate, end: event.endDate))
        .font(.system(size: 24, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)

      Spacer()

      HStack(spacing: 16) {
        if event.openURL != nil || event.calendarURL != nil {
          Button(joinButtonLabel, action: onJoin)
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("meetingAlert.join")
        }

        Button("Dismiss", action: onDismiss)
          .buttonStyle(.bordered)
          .controlSize(.extraLarge)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("meetingAlert.dismiss")
      }
      .padding(.bottom, 24)
    }
    .padding(.vertical, 48)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      VisualEffectBackdrop()
        .overlay(backdropColor.opacity(0.55))
        .ignoresSafeArea()
    }
    .onExitCommand(perform: onDismiss)
    .accessibilityIdentifier("meetingAlert.view")
  }

  /// Fully black in dark mode and white in light mode for the tinted blur backdrop.
  private var backdropColor: Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    }))
  }

  /// Lead text re-evaluated by the periodic TimelineView so it ticks down
  /// and flips to "Starting now" while the alert is visible.
  private var startLabel: String {
    let secondsUntilStart = event.startDate.timeIntervalSince(Date())
    guard secondsUntilStart > 30 else {
      return "Starting now"
    }
    let minutes = max(1, Int(ceil(secondsUntilStart / 60)))
    return minutes == 1 ? "Starts in 1 minute" : "Starts in \(minutes) minutes"
  }

  /// "Join Meeting" only when the open URL is a real meeting link; when it
  /// just falls back to the calendar page the honest label is "Open Event".
  private var joinButtonLabel: String {
    if event.openURL != nil, event.openURL != event.calendarURL {
      return "Join Meeting"
    }
    return "Open Event"
  }
}

/// AppKit vibrancy backdrop that blurs whatever sits behind the window.
private struct VisualEffectBackdrop: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
