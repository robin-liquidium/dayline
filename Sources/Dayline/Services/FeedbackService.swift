import Foundation

/// Submits intentionally entered feedback to Dayline's public issue relay.
struct FeedbackService {
  private let endpoint = URL(string: "https://dayline.robin.build/api/feedback")!

  /// Sends feedback and returns the public GitHub issue that was created.
  func submit(
    category: FeedbackCategory,
    message: String,
    includeAnonymousSystemInformation: Bool
  ) async throws -> FeedbackIssue {
    let submission = FeedbackSubmission(
      category: category,
      message: message.trimmingCharacters(in: .whitespacesAndNewlines),
      metadata: includeAnonymousSystemInformation ? .current : nil
    )

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("macOS", forHTTPHeaderField: "X-Dayline-Client")
    request.setValue("Dayline", forHTTPHeaderField: "User-Agent")
    request.httpBody = try JSONEncoder().encode(submission)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw FeedbackServiceError.invalidResponse
    }

    let decoder = JSONDecoder()
    if (200..<300).contains(httpResponse.statusCode),
       let issue = try? decoder.decode(FeedbackIssue.self, from: data) {
      return issue
    }

    if let errorResponse = try? decoder.decode(FeedbackErrorResponse.self, from: data) {
      throw FeedbackServiceError.rejected(errorResponse.error)
    }

    throw FeedbackServiceError.invalidResponse
  }
}

/// Anonymized product and platform details that contain no user or device identifiers.
struct FeedbackMetadata: Codable, Equatable {
  let appVersion: String
  let build: String
  let macOSVersion: String
  let architecture: String

  /// Current non-identifying build and platform values.
  static var current: FeedbackMetadata {
    let info = Bundle.main.infoDictionary
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion

    return FeedbackMetadata(
      appVersion: info?["CFBundleShortVersionString"] as? String ?? "Unknown",
      build: info?["CFBundleVersion"] as? String ?? "Unknown",
      macOSVersion: "\(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)",
      architecture: architectureName
    )
  }

  private static var architectureName: String {
    #if arch(arm64)
      "Apple Silicon"
    #elseif arch(x86_64)
      "Intel"
    #else
      "Unknown"
    #endif
  }
}

/// JSON body accepted by the feedback relay.
private struct FeedbackSubmission: Encodable {
  let category: FeedbackCategory
  let message: String
  let metadata: FeedbackMetadata?
}

/// Public issue details returned by the feedback relay.
struct FeedbackIssue: Decodable, Equatable {
  let issueURL: URL
  let issueNumber: Int
}

/// Compact API error returned by the feedback relay.
private struct FeedbackErrorResponse: Decodable {
  let error: String
}

enum FeedbackServiceError: LocalizedError {
  case invalidResponse
  case rejected(String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "Feedback could not be submitted. Please try again."
    case .rejected(let message):
      message
    }
  }
}
