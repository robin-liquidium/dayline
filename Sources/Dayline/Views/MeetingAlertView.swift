import SwiftUI

/// Zen full-screen alert shown when a meeting starts.
struct MeetingAlertView: View {
  let event: CalendarEventItem
  let onJoin: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.03, green: 0.04, blue: 0.09),
          Color(red: 0.07, green: 0.05, blue: 0.14)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        Text("DAYLINE")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .tracking(6)
          .foregroundStyle(.white.opacity(0.45))

        Spacer()

        Text(startLabel)
          .font(.system(size: 20, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.6))
          .padding(.bottom, 16)

        Text(event.title)
          .font(.system(size: 60, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 80)
          .padding(.bottom, 12)

        Text(DisplayFormatters.eventTimeRange(start: event.startDate, end: event.endDate))
          .font(.system(size: 24, weight: .regular, design: .rounded))
          .foregroundStyle(.white.opacity(0.6))

        Spacer()

        HStack(spacing: 16) {
          if event.openURL != nil || event.calendarURL != nil {
            Button("Join Meeting", action: onJoin)
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
    }
    .onExitCommand(perform: onDismiss)
    .accessibilityIdentifier("meetingAlert.view")
  }

  /// Static lead text resolved when the alert appears.
  private var startLabel: String {
    let secondsUntilStart = event.startDate.timeIntervalSince(Date())
    guard secondsUntilStart > 30 else {
      return "Starting now"
    }
    let minutes = max(1, Int(ceil(secondsUntilStart / 60)))
    return minutes == 1 ? "Starts in 1 minute" : "Starts in \(minutes) minutes"
  }
}
