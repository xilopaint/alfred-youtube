import Foundation

// MARK: - ChannelStats Struct

/// A struct representing statistics for a YouTube channel.
struct ChannelStats {
  let subscriberCount: Int
  let viewCount: Int
  let videoCount: Int
}

// MARK: - JSON Parsing Functions

/// Parses and processes channel information from the YouTube API's JSON response.
///
/// - Parameter json: A dictionary representing the JSON response from the YouTube API containing
///   channel snippets.
/// - Returns: An array of dictionaries containing formatted channel information compatible with
///   Alfred.
func parseChannelSnippetJSON(_ json: [String: Any]) -> [[String: Any]] {
  guard let items: [[String: Any]] = json["items"] as? [[String: Any]] else {
    fputs("Error: Unable to get items from JSON.", stderr)
    exit(1)
  }

  var parsedSnippetItems: [[String: Any]] = []

  for item: [String: Any] in items {
    if let id: [String: String] = item["id"] as? [String: String],
       let channelId: String = id["channelId"],
       let snippet: [String: Any] = item["snippet"] as? [String: Any],
       let rawTitle: String = snippet["title"] as? String,
       let publishedAt: String = snippet["publishedAt"] as? String,
       let description: String = snippet["description"] as? String {
      let title: String = decodeHTMLEntities(rawTitle)
      let elapsedTime: String = parseElapsedTime(from: publishedAt) ?? "Unknown time"

      let parsedSnippetItem: [String: Any] = [
        "channelId": channelId,
        "title": title,
        "elapsedTime": elapsedTime,
        "description": description,
      ]
      parsedSnippetItems.append(parsedSnippetItem)
    }
  }

  return parsedSnippetItems
}

/// Parses the JSON response from the YouTube API containing channel statistics and extracts
/// subscriber counts, view counts, and video counts.
///
/// - Parameter json: A dictionary representing the JSON response from the YouTube API containing
///   channel statistics.
/// - Returns: A dictionary with video IDs as keys and `ChannelStats` instances containing the
///   subscriber count, view count, and video count as values.
func parseChannelStatisticsJSON(_ json: [String: Any]) -> [String: ChannelStats] {
  guard let items: [[String: Any]] = json["items"] as? [[String: Any]] else { return [:] }

  var channelStats: [String: ChannelStats] = [:]

  for item: [String: Any] in items {
    if let id: String = item["id"] as? String,
       let statistics: [String: Any] = item["statistics"] as? [String: Any],
       let subCount = Int(statistics["subscriberCount"] as? String ?? "0"),
       let viewCount = Int(statistics["viewCount"] as? String ?? "0"),
       let videoCount = Int(statistics["videoCount"] as? String ?? "0") {
      channelStats[id] = ChannelStats(
        subscriberCount: subCount,
        viewCount: viewCount,
        videoCount: videoCount
      )
    }
  }

  return channelStats
}

// MARK: - Alfred Feedback Generation

/// Combines the results of `parseChannelSnippetJSON` and `parseChannelStatisticsJSON` to create an
/// array of dictionaries in Alfred's feedback format.
///
/// - Parameters:
/// - items: An array of dictionaries in the format returned by `parseVideoSnippetJSON`.
/// - channelStats: A dictionary with video IDs as keys and `ChannelStats` instances containing the
///   subscriber count, view count, and video count as values returned by `parseVideoStatisticsJSON`.
/// - Returns: A dictionary containing an `items` key with an array of dictionaries in the format
///   expected by Alfred.
func createAlfredChannelItems(
  from items: [[String: Any]],
  with channelStats: [String: ChannelStats]
) -> [String: [[String: Any]]] {
  var alfredItems: [[String: Any]] = []

  for item: [String: Any] in items {
    let channelId: String = item["channelId"] as? String ?? ""
    let title: String = item["title"] as? String ?? ""
    let stats: ChannelStats = channelStats[channelId] ??
      ChannelStats(subscriberCount: 0, viewCount: 0, videoCount: 0)
    let subCount: String = formatCount(stats.subscriberCount)
    let viewCount: String = formatCount(stats.viewCount)
    let videoCount: String = formatCount(stats.videoCount)
    let elapsedTime: String = item["elapsedTime"] as? String ?? ""
    let description: String = item["description"] as? String ?? ""

    let alfredItem: [String: Any] = [
      "title": title,
      "subtitle": "\(subCount) subscribers • \(viewCount) views • \(videoCount) videos • created \(elapsedTime)",
      "arg": "https://www.youtube.com/channel/\(channelId)",
      "mods": [
        "cmd": [
          "subtitle": "\(description)",
        ],
      ],
    ]

    alfredItems.append(alfredItem)
  }

  return ["items": alfredItems]
}

// MARK: - Response Handling

/// Handles the response from the YouTube API's search endpoint and prints the resulting Alfred
/// feedback.
///
/// - Parameter apiKey: The YouTube API key used to authenticate the request.
/// - Returns: A closure that takes `Data?`, `URLResponse?`, and `Error?` as arguments.
func handleChannelResponse(apiKey: String) -> (Data?, URLResponse?, Error?) -> Void {
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
      let items: [[String: Any]] = parseChannelSnippetJSON(json)
      let channelIds: String = items.compactMap { $0["channelId"] as? String }
        .joined(separator: ",")

      let endpoint = "https://www.googleapis.com/youtube/v3/channels"
      let queryParams: [String: String] = ["part": "statistics", "id": channelIds, "key": apiKey]

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

        let channelStats: [String: ChannelStats] = parseChannelStatisticsJSON(json)

        let alfredItems: [String: [[String: Any]]] = createAlfredChannelItems(
          from: items,
          with: channelStats
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
