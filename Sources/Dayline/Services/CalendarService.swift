import Foundation

/// Identity and calendar catalog discovered for one authenticated Google account.
struct GoogleAccountDiscovery: Sendable {
  let providerAccountID: String
  let displayLabel: String
  let calendars: [GoogleCalendarSource]
}

/// Fetches and normalizes calendar metadata and events from the Google Calendar API.
struct CalendarService: Sendable {
  /// OAuth session supplying one Google account's access tokens.
  let authSession: OAuthSession

  init(authSession: OAuthSession = .google) {
    self.authSession = authSession
  }

  /// Loads the primary identity and complete readable calendar catalog for one account.
  func fetchAccountDiscovery() async throws -> GoogleAccountDiscovery {
    async let identity = fetchPrimaryCalendarIdentity()
    async let calendars = fetchCalendarSources()
    let (resolvedIdentity, resolvedCalendars) = try await (identity, calendars)
    return GoogleAccountDiscovery(
      providerAccountID: resolvedIdentity.id,
      displayLabel: resolvedIdentity.id,
      calendars: resolvedCalendars
    )
  }

  /// Loads the connected Google account label for compatibility with existing call sites.
  func fetchAccountLabel() async throws -> String {
    try await fetchPrimaryCalendarIdentity().id
  }

  /// Loads all calendars for which event details are readable, including hidden entries.
  func fetchCalendarSources() async throws -> [GoogleCalendarSource] {
    var sources: [GoogleCalendarSource] = []
    var pageToken: String?

    repeat {
      var components = URLComponents()
      components.scheme = "https"
      components.host = "www.googleapis.com"
      components.path = "/calendar/v3/users/me/calendarList"
      components.queryItems = [
        URLQueryItem(name: "maxResults", value: "250"),
        URLQueryItem(name: "minAccessRole", value: "reader"),
        URLQueryItem(name: "showDeleted", value: "false"),
        URLQueryItem(name: "showHidden", value: "true")
      ]
      if let pageToken {
        components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
      }

      guard let url = components.url else {
        throw OAuthError.httpError(-1, "Could not build the Google calendar list URL.")
      }

      let data = try await authSession.authorizedData(for: URLRequest(url: url))
      let response = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
      sources.append(contentsOf: (response.items ?? []).map { entry in
        GoogleCalendarSource(
          id: entry.id,
          name: entry.displayName,
          isPrimary: entry.primary ?? false,
          isEnabled: entry.selected ?? false
        )
      })
      pageToken = response.nextPageToken
    } while pageToken != nil

    return sources
  }

  /// Loads timed events from one enabled calendar in a bounded agenda window.
  func fetchEvents(
    accountID: UUID,
    calendar: GoogleCalendarSource,
    from startDate: Date,
    to endDate: Date,
    cutoff: Date
  ) async throws -> [CalendarEventItem] {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    isoFormatter.formatOptions = [.withInternetDateTime]

    var events: [CalendarEventItem] = []
    var pageToken: String?

    repeat {
      var components = URLComponents()
      components.scheme = "https"
      components.host = "www.googleapis.com"
      components.percentEncodedPath = "/calendar/v3/calendars/\(Self.percentEncode(calendar.id))/events"
      components.queryItems = [
        URLQueryItem(name: "timeMin", value: isoFormatter.string(from: startDate)),
        URLQueryItem(name: "timeMax", value: isoFormatter.string(from: endDate)),
        URLQueryItem(name: "singleEvents", value: "true"),
        URLQueryItem(name: "orderBy", value: "startTime"),
        URLQueryItem(name: "maxResults", value: "2500")
      ]
      if let pageToken {
        components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
      }

      guard let url = components.url else {
        throw OAuthError.httpError(-1, "Could not build the Google Calendar request URL.")
      }

      let data = try await authSession.authorizedData(for: URLRequest(url: url))
      let response = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)
      events.append(contentsOf: (response.items ?? []).compactMap {
        $0.displayItem(accountID: accountID, calendar: calendar, now: cutoff)
      })
      pageToken = response.nextPageToken
    } while pageToken != nil

    return events.sorted { $0.startDate < $1.startDate }
  }

  /// Loads the primary calendar identity, whose ID is the stable Google account email.
  private func fetchPrimaryCalendarIdentity() async throws -> GoogleCalendarIdentity {
    let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary")!
    let data = try await authSession.authorizedData(for: URLRequest(url: url))
    return try JSONDecoder().decode(GoogleCalendarIdentity.self, from: data)
  }

  /// Percent-encodes one URL path component using strict RFC 3986 unreserved characters.
  private static func percentEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}

/// Primary calendar identity used to identify a Google account.
private struct GoogleCalendarIdentity: Decodable {
  let id: String
}

/// Paginated response returned by CalendarList.list.
private struct GoogleCalendarListResponse: Decodable {
  let items: [GoogleCalendarListEntry]?
  let nextPageToken: String?
}

/// One readable calendar in a Google account's calendar list.
private struct GoogleCalendarListEntry: Decodable {
  let id: String
  let summary: String?
  let summaryOverride: String?
  let primary: Bool?
  let selected: Bool?

  var displayName: String {
    let preferred = summaryOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !preferred.isEmpty {
      return preferred
    }
    let fallback = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return fallback.isEmpty ? id : fallback
  }
}

/// Paginated response returned by Events.list.
private struct GoogleCalendarEventsResponse: Decodable {
  let items: [GoogleCalendarEvent]?
  let nextPageToken: String?
}

/// Google Calendar event shape used by the app.
private struct GoogleCalendarEvent: Decodable {
  let id: String
  let iCalUID: String?
  let status: String?
  let summary: String?
  let start: GoogleCalendarEventDate
  let end: GoogleCalendarEventDate
  let originalStartTime: GoogleCalendarEventDate?
  let location: String?
  let hangoutLink: String?
  let conferenceData: GoogleCalendarConferenceData?
  let htmlLink: String?

  /// Converts a Google event into one account- and calendar-scoped display item.
  func displayItem(accountID: UUID, calendar: GoogleCalendarSource, now: Date) -> CalendarEventItem? {
    guard status != "cancelled",
          let startDate = start.resolvedDate,
          let endDate = end.resolvedDate,
          endDate > now else {
      return nil
    }

    let occurrenceDate = originalStartTime?.resolvedDate ?? startDate
    let deduplicationKey = iCalUID.map { "\($0)|\(occurrenceDate.timeIntervalSince1970)" }
    return CalendarEventItem(
      id: CalendarEventItem.compositeID(accountID: accountID, calendarID: calendar.id, eventID: id),
      title: (summary?.isEmpty == false ? summary : "Untitled event") ?? "Untitled event",
      startDate: startDate,
      endDate: endDate,
      location: location,
      calendarURL: htmlLink.flatMap(URL.init(string:)),
      openURL: preferredOpenURL,
      sourceCalendarNames: [calendar.name],
      sourceIDs: [CalendarEventItem.sourceID(accountID: accountID, calendarID: calendar.id)],
      deduplicationKey: deduplicationKey
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

private struct GoogleCalendarConferenceData: Decodable {
  let entryPoints: [GoogleCalendarEntryPoint]?
}

private struct GoogleCalendarEntryPoint: Decodable {
  let entryPointType: String?
  let uri: String?

  var url: URL? {
    uri.flatMap(URL.init(string:))
  }
}

/// Google Calendar date wrapper; all-day dates intentionally resolve to nil.
private struct GoogleCalendarEventDate: Decodable {
  let dateTime: String?
  let date: String?
  let timeZone: String?

  var resolvedDate: Date? {
    guard let dateTime else {
      return nil
    }
    return DateParsers.rfc3339Date(from: dateTime)
  }
}
