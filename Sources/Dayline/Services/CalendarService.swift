import Foundation

/// Fetches and normalizes upcoming events from the Google Calendar API.
struct CalendarService {
  /// OAuth session supplying Google access tokens.
  var authSession: OAuthSession = .google

  /// Loads timed events between now and the end of the local day.
  func fetchUpcomingEvents(now: Date = Date(), limit: Int = 6) async throws -> [CalendarEventItem] {
    let calendar = Calendar.current
    let endOfDay = calendar.dateInterval(of: .day, for: now)?.end.addingTimeInterval(-1) ?? now.addingTimeInterval(6 * 60 * 60)
    return try await fetchEvents(from: now, to: endOfDay, cutoff: now, limit: limit)
  }

  /// Loads timed events for tomorrow.
  func fetchTomorrowEvents(now: Date = Date(), limit: Int = 8) async throws -> [CalendarEventItem] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(24 * 60 * 60)
    let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrow)?.addingTimeInterval(-1) ?? tomorrow.addingTimeInterval(24 * 60 * 60 - 1)
    return try await fetchEvents(from: tomorrow, to: endOfTomorrow, cutoff: tomorrow, limit: limit)
  }

  /// Loads the connected Google account label for Settings.
  func fetchAccountLabel() async throws -> String {
    let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary")!
    let data = try await authSession.authorizedData(for: URLRequest(url: url))
    let calendar = try JSONDecoder().decode(GoogleCalendarIdentity.self, from: data)
    let summary = calendar.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !summary.isEmpty {
      return summary
    }
    return calendar.id
  }

  /// Loads timed events in a bounded calendar range.
  private func fetchEvents(from startDate: Date, to endDate: Date, cutoff: Date, limit: Int) async throws -> [CalendarEventItem] {
    // Always emit UTC `...Z` timestamps so `+` offsets are never misread as spaces in query strings.
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    isoFormatter.formatOptions = [.withInternetDateTime]

    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.googleapis.com"
    components.path = "/calendar/v3/calendars/primary/events"
    components.percentEncodedQuery = [
      "timeMin": isoFormatter.string(from: startDate),
      "timeMax": isoFormatter.string(from: endDate),
      "singleEvents": "true",
      "orderBy": "startTime",
      "maxResults": String(max(limit * 3, 12)),
      "timeZone": TimeZone.current.identifier
    ]
    .map { key, value in
      "\(Self.percentEncode(key))=\(Self.percentEncode(value))"
    }
    .joined(separator: "&")

    guard let url = components.url else {
      throw OAuthError.httpError(-1, "Could not build Google Calendar request URL.")
    }

    let data = try await authSession.authorizedData(for: URLRequest(url: url))
    let response = try JSONDecoder().decode(GoogleCalendarResponse.self, from: data)
    return (response.items ?? [])
      .compactMap { $0.displayItem(now: cutoff) }
      .sorted { $0.startDate < $1.startDate }
      .prefix(limit)
      .map { $0 }
  }

  /// Percent-encodes a query component, including `+` and other reserved characters.
  private static func percentEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}

/// Primary calendar identity used for Settings account display.
private struct GoogleCalendarIdentity: Decodable {
  /// Calendar ID, commonly the account email for the primary calendar.
  let id: String

  /// Human-readable calendar title.
  let summary: String?
}

/// Top-level response returned by Google Calendar's events list endpoint.
private struct GoogleCalendarResponse: Decodable {
  /// Event objects returned by Google Calendar.
  let items: [GoogleCalendarEvent]?
}

/// Google Calendar event shape used by the app.
private struct GoogleCalendarEvent: Decodable {
  /// Event identifier.
  let id: String

  /// Event status such as `confirmed` or `cancelled`.
  let status: String?

  /// Event summary.
  let summary: String?

  /// Event start payload.
  let start: GoogleCalendarEventDate

  /// Event end payload.
  let end: GoogleCalendarEventDate

  /// Optional event location.
  let location: String?

  /// Legacy Google Meet link supplied directly on the event.
  let hangoutLink: String?

  /// Structured conferencing payload supplied by Google Calendar.
  let conferenceData: GoogleCalendarConferenceData?

  /// Browser URL for the event.
  let htmlLink: String?

  /// Converts a Google event into a timed display item.
  func displayItem(now: Date) -> CalendarEventItem? {
    guard status != "cancelled",
          let startDate = start.resolvedDate,
          let endDate = end.resolvedDate,
          endDate > now else {
      return nil
    }

    return CalendarEventItem(
      id: id,
      title: (summary?.isEmpty == false ? summary : "Untitled event") ?? "Untitled event",
      startDate: startDate,
      endDate: endDate,
      location: location,
      calendarURL: htmlLink.flatMap(URL.init(string:)),
      openURL: preferredOpenURL
    )
  }

  /// Best URL to open when the user clicks the event row.
  private var preferredOpenURL: URL? {
    conferenceURL ?? location.flatMap(Self.firstURL(in:)) ?? htmlLink.flatMap(URL.init(string:))
  }

  /// Best structured conferencing URL from Google Calendar.
  private var conferenceURL: URL? {
    if let hangoutURL = hangoutLink.flatMap(URL.init(string:)) {
      return hangoutURL
    }

    let entries = conferenceData?.entryPoints ?? []
    return entries.first(where: { $0.entryPointType == "video" })?.url
      ?? entries.first(where: { $0.url != nil })?.url
  }

  /// Finds the first URL embedded in a location string.
  private static func firstURL(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return detector?.firstMatch(in: text, options: [], range: range)?.url
  }
}

/// Structured conferencing information on a Google Calendar event.
private struct GoogleCalendarConferenceData: Decodable {
  /// Join options such as video, phone, and SIP entry points.
  let entryPoints: [GoogleCalendarEntryPoint]?
}

/// One conferencing entry point returned by Google Calendar.
private struct GoogleCalendarEntryPoint: Decodable {
  /// Entry point type, commonly `video` for Google Meet links.
  let entryPointType: String?

  /// Join URL string for this entry point.
  let uri: String?

  /// Parsed join URL when the entry point is web-openable.
  var url: URL? {
    uri.flatMap(URL.init(string:))
  }
}

/// Google Calendar date wrapper that can contain either a timed date or an all-day date.
private struct GoogleCalendarEventDate: Decodable {
  /// RFC3339 timestamp for timed events.
  let dateTime: String?

  /// Calendar date for all-day events.
  let date: String?

  /// Time zone identifier supplied by Google Calendar.
  let timeZone: String?

  /// Parsed date for timed events; all-day dates are intentionally ignored.
  var resolvedDate: Date? {
    guard let dateTime else {
      return nil
    }
    return DateParsers.rfc3339Date(from: dateTime)
  }
}
