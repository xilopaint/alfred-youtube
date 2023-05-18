import Foundation

// MARK: - JSON Parsing Functions

/// Parses and processes video information from the YouTube API's JSON response.
///
/// - Parameter json: A dictionary representing the JSON response from the YouTube API containing
///   video snippets.
/// - Returns: An array of dictionaries containing formatted video information compatible with
///   Alfred.
func parseVideoSnippetJSON(_ json: [String: Any]) -> [[String: Any]] {
  guard let items: [[String: Any]] = json["items"] as? [[String: Any]] else {
    fputs("Error: Unable to get items from JSON.", stderr)
    exit(1)
  }

  var parsedSnippetItems: [[String: Any]] = []

  for item: [String: Any] in items {
    if let id: [String: String] = item["id"] as? [String: String],
       let videoId: String = id["videoId"],
       let snippet: [String: Any] = item["snippet"] as? [String: Any],
       let rawTitle: String = snippet["title"] as? String,
       let rawChannelTitle: String = snippet["channelTitle"] as? String,
       let publishedAt: String = snippet["publishedAt"] as? String {
      let title: String = decodeHTMLEntities(rawTitle)
      let channelTitle: String = decodeHTMLEntities(rawChannelTitle)
      let elapsedTime: String = parseElapsedTime(from: publishedAt) ?? "Unknown time"

      // Create a result item with video and channel information
      let parsedSnippetItem: [String: String] = [
        "videoId": videoId,
        "title": title,
        "channelTitle": channelTitle,
        "elapsedTime": elapsedTime,
      ]
      parsedSnippetItems.append(parsedSnippetItem)
    }
  }

  return parsedSnippetItems
}

/// Parses the JSON response from the YouTube API containing video statistics and extracts view
/// counts.
///
/// - Parameter json: A dictionary representing the JSON response from the YouTube API containing
///   video statistics.
/// - Returns: A dictionary with video IDs as keys and view counts as values.
func parseVideoStatisticsJSON(_ json: [String: Any]) -> [String: Int] {
  guard let items: [[String: Any]] = json["items"] as? [[String: Any]] else { return [:] }

  var viewCounts: [String: Int] = [:]

  for item: [String: Any] in items {
    if let id: String = item["id"] as? String,
       let statistics: [String: Any] = item["statistics"] as? [String: Any],
       let viewCount = Int(statistics["viewCount"] as? String ?? "0") {
      viewCounts[id] = viewCount
    }
  }

  return viewCounts
}

// MARK: - Alfred Feedback Generation

/// Combines the results of `parseVideoSnippetJSON` and `parseVideoStatisticsJSON` into a
/// dictionary formatted according to Alfred's feedback format.
///
/// - Parameters:
/// - items: An array of dictionaries in the format returned by `parseVideoSnippetJSON`.
/// - viewCounts: A dictionary with video IDs as keys and view counts as values returned by
///   `parseVideoStatisticsJSON`.
/// - Returns: A dictionary containing an `items` key with an array of dictionaries in the format
///   expected by Alfred.
func createAlfredVideoItems(
  from items: [[String: Any]],
  with viewCounts: [String: Int]
) -> [String: [[String: Any]]] {
  var alfredItems: [[String: Any]] = []

  for item: [String: Any] in items {
    guard let videoId: String = item["videoId"] as? String,
          let channelTitle: String = item["channelTitle"] as? String,
          let elapsedTime: String = item["elapsedTime"] as? String,
          let title: String = item["title"] as? String
    else {
      continue
    }

    let arg = "https://www.youtube.com/watch?v=\(videoId)"
    let rawViewCount: Int = viewCounts[videoId] ?? 0
    let viewCount: String = formatCount(rawViewCount)
    let subtitle = "\(channelTitle) • \(viewCount) views • \(elapsedTime)"

    let alfredItem: [String: Any] = [
      "videoId": videoId,
      "title": title,
      "subtitle": subtitle,
      "arg": arg,
    ]
    alfredItems.append(alfredItem)
  }

  return ["items": alfredItems]
}

// MARK: - Response Handling

/// Handles the response from the YouTube API's search endpoint, sends a request to the videos
/// endpoint, and prints the resulting Alfred feedback.
///
/// - Parameter apiKey: The YouTube API key used to authenticate the request.
/// - Returns: A closure that takes `Data?`, `URLResponse?`, and `Error?` as arguments.
func handleVideoResponse(apiKey: String) -> (Data?, URLResponse?, Error?) -> Void {
  { data, _, error in
    // Check for network errors.
    guard let data: Data = data, error == nil else {
      fputs(".\nError: \(error?.localizedDescription ?? "Unknown error.")", stderr)
      exit(1)
    }

    // Parse the JSON object into a dictionary, or display an error message if unsuccessful.
    guard let json: [String: Any] = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      fputs(".\nError: Unable to parse JSON.", stderr)
      exit(1)
    }

    // Check if there's an error in the API response.
    if let apiError: [String: Any] = json["error"] as? [String: Any] {
      handleAPIError(apiError)
    } else {
      let items: [[String: Any]] = parseVideoSnippetJSON(json)
      let videoIds: String = items.compactMap { $0["videoId"] as? String }.joined(separator: ",")

      let endpoint = "https://www.googleapis.com/youtube/v3/videos"
      let queryParams: [String: String] = ["part": "statistics", "id": videoIds, "key": apiKey]

      guard let url: URL = buildURL(with: endpoint, using: queryParams) else {
        fputs("Error: Unable to build URL.", stderr)
        exit(1)
      }

      URLSession.shared.dataTask(with: url) { data, _, error in
        guard let data: Data = data, error == nil else {
          fputs(".\nError: \(error?.localizedDescription ?? "Unknown error")", stderr)
          exit(1)
        }

        guard let json: [String: Any] = try? JSONSerialization
          .jsonObject(with: data) as? [String: Any] else {
          fputs(".\nError: Unable to parse JSON.", stderr)
          exit(1)
        }

        let viewCounts: [String: Int] = parseVideoStatisticsJSON(json)

        let alfredItems: [String: [[String: Any]]] = createAlfredVideoItems(
          from: items,
          with: viewCounts
        )

        do {
          let alfredFeedback: Data = try serializeJSON(alfredItems)
          print(String(data: alfredFeedback, encoding: .utf8)!)
          exit(0)
        } catch {
          fputs(".\nError: Unable to serialize JSON.", stderr)
          exit(1)
        }
      }.resume()
    }
  }
}
