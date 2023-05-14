import Foundation

// MARK: - URL Building

/// Builds a URL with the specified endpoint and query parameters.
///
/// - Parameters:
///   - endpoint: The API endpoint as a string.
///   - queryParams: A dictionary of query parameters where the key is the parameter name and the
///     value is the parameter value.
/// - Returns: An optional `URL` constructed using the given endpoint and query parameters.
func buildURL(with endpoint: String, using queryParams: [String: String]) -> URL? {
  guard var components = URLComponents(string: endpoint) else { return nil }
  components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
  return components.url
}

// MARK: - Text Processing

/// Decodes HTML entities in the given string.
///
/// - Parameter rawEntity: A string containing HTML entities.
/// - Returns: A new string with HTML entities replaced with their corresponding characters.
func decodeHTMLEntities(_ rawEntity: String) -> String {
  guard let processedEntity: CFString = CFXMLCreateStringByUnescapingEntities(
    nil,
    rawEntity as CFString,
    nil
  ) else {
    return rawEntity as String
  }
  return processedEntity as String
}

/// Formats a given count as a readable string with appropriate suffixes.
///
/// - Parameter count: An integer representing the count to be formatted.
/// - Returns: A formatted string representing the count with appropriate suffixes.
func formatCount(_ count: Int) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.maximumFractionDigits = 1
  formatter.locale = Locale(identifier: "en_US")

  if count >= 1_000_000_000 {
    let billions = Double(count) / 1_000_000_000.0
    let formatted: String = formatter.string(from: NSNumber(value: billions)) ?? String(billions)
    return "\(formatted)B"
  } else if count >= 1_000_000 {
    let millions = Double(count) / 1_000_000.0
    let formatted: String = formatter.string(from: NSNumber(value: millions)) ?? String(millions)
    return "\(formatted)M"
  } else if count >= 1000 {
    let thousands = Double(count) / 1000.0
    let formatted: String = formatter.string(from: NSNumber(value: thousands)) ?? String(thousands)
    return "\(formatted)K"
  } else {
    return "\(count)"
  }
}

/// Parses the elapsed time since a video or channel was published into a human-readable string.
///
/// - Parameter publishedAt: The video or channel published date in ISO 8601 format.
/// - Returns: An optional string representing the elapsed time since the video or channel was
///   published, or `nil` if the input is not valid.
func parseElapsedTime(from publishedAt: String) -> String? {
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
  dateFormatter.locale = Locale(identifier: "en_US_POSIX")

  guard let date: Date = dateFormatter.date(from: publishedAt) else { return nil }

  let calendar = Calendar.current
  let dateComponents: DateComponents = calendar.dateComponents(
    [.year, .month, .day, .hour, .minute],
    from: date,
    to: Date()
  )

  if let years: Int = dateComponents.year, years > 0 {
    return "\(years) year\(years > 1 ? "s" : "") ago"
  } else if let months: Int = dateComponents.month, months > 0 {
    return "\(months) month\(months > 1 ? "s" : "") ago"
  } else if let days: Int = dateComponents.day, days > 0 {
    if days >= 14, days <= 31 {
      let weeks: Int = days / 7
      return "\(weeks) week\(weeks > 1 ? "s" : "") ago"
    }
    return "\(days) day\(days > 1 ? "s" : "") ago"
  } else if let hours: Int = dateComponents.hour, hours > 0 {
    return "\(hours) hour\(hours > 1 ? "s" : "") ago"
  } else if let minutes: Int = dateComponents.minute, minutes > 0 {
    return "\(minutes) minute\(minutes > 1 ? "s" : "") ago"
  }

  return "Just now"
}

// MARK: - JSON Handling

/// Serializes the provided `alfredItems` dictionary into JSON data.
///
/// - Parameter alfredItems: A dictionary containing items in the format expected by Alfred.
/// - Throws: If the provided dictionary cannot be serialized into JSON data.
/// - Returns: The JSON data representation of `alfredItems`.
func serializeJSON(_ alfredItems: [String: [[String: Any]]]) throws -> Data {
  try JSONSerialization.data(withJSONObject: alfredItems, options: .prettyPrinted)
}

// MARK: - Error Handling

/// Handles API error responses by extracting the relevant error information and displaying it.
///
/// - Parameter errorInfo: A dictionary containing error information.
func handleAPIError(_ errorInfo: [String: Any]) {
  if let code: Int = errorInfo["code"] as? Int,
     let rawMessage: String = errorInfo["message"] as? String,
     let errors: [[String: Any]] = errorInfo["errors"] as? [[String: Any]],
     let firstError: [String: Any] = errors.first {
    let message: String = rawMessage.replacingOccurrences(
      of: "<[^>]+>",
      with: "",
      options: .regularExpression
    )
    let reason: String = firstError["reason"] as? String ?? "Unknown reason"
    let extendedHelp: String = firstError["extendedHelp"] as? String ?? "No extended help available"
    fputs(
      ".\nError Code: \(code)\nMessage: \(message)\nReason: \(reason)\nExtended Help: \(extendedHelp)",
      stderr
    )
  } else {
    fputs(".\nAPI Error: Unable to parse error information.", stderr)
  }

  exit(1)
}
