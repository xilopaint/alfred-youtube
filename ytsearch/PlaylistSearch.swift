import Foundation

// MARK: - JSON Parsing Functions

/// Parses and processes playlist information from the YouTube API's JSON response.
///
/// - Parameter json: A dictionary representing the JSON response from the YouTube API containing
///   playlist snippets.
/// - Returns: An array of dictionaries containing formatted video information compatible with
///   Alfred.
func parsePlaylistSnippetJSON(_ json: [String: Any]) -> [[String: Any]] {
    guard let items: [[String: Any]] = json["items"] as? [[String: Any]] else {
        fputs("Error: Unable to get items from JSON.", stderr)
        exit(1)
    }

    var parsedSnippetItems: [[String: Any]] = []

    for item: [String: Any] in items {
        if let id: [String: String] = item["id"] as? [String: String],
           let playlistId: String = id["playlistId"],
           let snippet: [String: Any] = item["snippet"] as? [String: Any],
           let rawTitle: String = snippet["title"] as? String,
           let rawChannelTitle: String = snippet["channelTitle"] as? String,
           let publishedAt: String = snippet["publishedAt"] as? String {
            let title: String = decodeHTMLEntities(rawTitle)
            let channelTitle: String = decodeHTMLEntities(rawChannelTitle)
            let elapsedTime: String = parseElapsedTime(from: publishedAt) ?? "Unknown time"

            // Create a result item with playlist and channel information
            let parsedSnippetItem: [String: String] = [
                "playlistId": playlistId,
                "title": title,
                "channelTitle": channelTitle.isEmpty ? "YouTube Music" : channelTitle,
                "elapsedTime": elapsedTime,
            ]
            parsedSnippetItems.append(parsedSnippetItem)
        }
    }

    return parsedSnippetItems
}

// MARK: - Alfred Feedback Generation

/// Converts the results of `parsePlaylistSnippetJSON` into a dictionary in Alfred's feedback
/// format.
///
/// - Parameters:
/// - items: An array of dictionaries in the format returned by `parsePlaylistSnippetJSON`.
/// - Returns: A dictionary containing an `items` key with an array of dictionaries in the format
///   expected by Alfred.
func createAlfredPlaylistItems(from items: [[String: Any]]) -> [String: [[String: Any]]] {
    var alfredItems: [[String: Any]] = []

    for item: [String: Any] in items {
        guard let playlistId: String = item["playlistId"] as? String,
              let channelTitle: String = item["channelTitle"] as? String,
              let elapsedTime: String = item["elapsedTime"] as? String,
              let title: String = item["title"] as? String
        else {
            continue
        }

        let arg = "https://www.youtube.com/playlist?list=\(playlistId)"
        let subtitle = "\(channelTitle) • \(elapsedTime)"

        let alfredItem: [String: Any] = [
            "playlistId": playlistId,
            "title": title,
            "subtitle": subtitle,
            "arg": arg,
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
func handlePlaylistResponse(apiKey: String) -> (Data?, URLResponse?, Error?) -> Void {
    { data, _, error in
        // Check for network errors.
        guard let data: Data = data, error == nil else {
            fputs(".\nError: \(error?.localizedDescription ?? "Unknown error.")", stderr)
            exit(1)
        }
        fputs(
            "Raw JSON Response: \(String(data: data, encoding: .utf8) ?? "Unable to decode data.")",
            stderr
        )

        // Parse the JSON object into a dictionary, or display an error message if unsuccessful.
        guard let json: [String: Any] = try? JSONSerialization
            .jsonObject(with: data) as? [String: Any]
        else {
            fputs(".\nError: Unable to parse JSON.", stderr)
            exit(1)
        }
        fputs("Parsed JSON: \(json)", stderr)

        // Check if there's an error in the API response.
        if let apiError: [String: Any] = json["error"] as? [String: Any] {
            handleAPIError(apiError)
        } else {
            let items: [[String: Any]] = parsePlaylistSnippetJSON(json)

            let alfredItems: [String: [[String: Any]]] = createAlfredPlaylistItems(from: items)

            do {
                let alfredFeedback: Data = try serializeJSON(alfredItems)
                print(String(data: alfredFeedback, encoding: .utf8)!)
                exit(0)
            } catch {
                fputs(".\nError: Unable to serialize JSON.", stderr)
                exit(1)
            }
        }
    }
}
