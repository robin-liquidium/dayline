import SwiftUI

/// Native sheet for submitting anonymous feedback as a public GitHub issue.
struct FeedbackView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  @State private var category = FeedbackCategory.bug
  @State private var message = ""
  @State private var includesAnonymousSystemInformation = true
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var submittedIssue: FeedbackIssue?

  private let feedbackService = FeedbackService()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Submit Feedback")
        .font(.title2.weight(.semibold))

      if let submittedIssue {
        submittedContent(submittedIssue)
      } else {
        formContent
      }
    }
    .padding(20)
    .frame(width: 500)
    .frame(minHeight: 420)
    .interactiveDismissDisabled(isSubmitting)
  }

  private var formContent: some View {
    Group {
      Picker("Type", selection: $category) {
        ForEach(FeedbackCategory.allCases) { category in
          Text(category.label).tag(category)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("feedback.category")

      Text("What would you like us to know?")
        .font(.headline)

      TextEditor(text: $message)
        .accessibilityLabel("Feedback message")
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.04))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.primary.opacity(0.08))
        }
        .frame(minHeight: 180)
        .accessibilityIdentifier("feedback.message")

      Toggle("Include anonymous app and system information", isOn: $includesAnonymousSystemInformation)
        .accessibilityIdentifier("feedback.includeSystemInformation")

      Text("Includes only the Dayline version, macOS version, and chip type. The feedback report never includes your name, device name, IP address, accounts, calendar, Linear data, notes, tokens, or logs.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Label(
        "Your feedback and selected system information will be posted publicly in the Dayline GitHub repository. Do not include personal or sensitive information.",
        systemImage: "exclamationmark.triangle"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("feedback.error")
      }

      HStack {
        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isSubmitting)
        .accessibilityIdentifier("feedback.cancel")

        Button(isSubmitting ? "Submitting..." : "Submit") {
          Task { await submit() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit)
        .accessibilityIdentifier("feedback.submit")
      }
    }
  }

  private func submittedContent(_ issue: FeedbackIssue) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Thanks — feedback submitted as issue #\(issue.issueNumber).", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityIdentifier("feedback.success")

      Text("The issue is public, so you can view it on GitHub without signing in.")
        .foregroundStyle(.secondary)

      HStack {
        Spacer()

        Button("View on GitHub") {
          openURL(issue.issueURL)
        }

        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var canSubmit: Bool {
    !isSubmitting && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
  }

  private func submit() async {
    guard canSubmit else {
      return
    }

    isSubmitting = true
    errorMessage = nil

    do {
      submittedIssue = try await feedbackService.submit(
        category: category,
        message: message,
        includeAnonymousSystemInformation: includesAnonymousSystemInformation
      )
    } catch {
      errorMessage = error.localizedDescription
    }

    isSubmitting = false
  }
}
