import Foundation

/// Main entry point of the CLI that sends a request to the YouTube API.
func main() {
  // Check if the command line arguments have the required count.
  guard CommandLine.arguments.count == 3 else {
    fputs("usage: ytsearch <video | channel> <query>", stderr)
    exit(1)
  }

  // Validate search type as positional argument.
  guard CommandLine.arguments[1] == "video" || CommandLine.arguments[1] == "channel" else {
    fputs("usage: ytsearch <video | channel> <query>", stderr)
    exit(1)
  }

  // Retrieve search type and search query from command line arguments.
  let searchType = CommandLine.arguments[1]
  let searchQuery = CommandLine.arguments[2]

  // Access API key, max results and sort criteria from environment variables.
  let apiKey: String = ProcessInfo.processInfo.environment["api_key"]!
  let maxResults: String = ProcessInfo.processInfo.environment["max_results"]!
  let order: String = ProcessInfo.processInfo.environment["order"]!

  // Define YouTube API endpoint and query parameters.
  let endpoint = "https://www.googleapis.com/youtube/v3/search"
  let queryParams: [String: String] = [
    "part": "snippet",
    "maxResults": maxResults,
    "order": order,
    "q": searchQuery,
    "type": searchType,
    "key": apiKey,
  ]

  // Build the YouTube API request URL.
  guard let url: URL = buildURL(with: endpoint, using: queryParams) else {
    fputs("Error: Unable to build URL.", stderr)
    exit(1)
  }

  // Set response handler based on search type.
  let handleResponse = searchType == "video" ? handleVideoResponse(apiKey: apiKey) :
    handleChannelResponse(apiKey: apiKey)

  // Make an HTTP request to the YouTube API and process the response.
  let task: URLSessionDataTask = URLSession.shared.dataTask(
    with: url,
    completionHandler: handleResponse
  )
  task.resume()

  // Keep the script running until all the asynchronous tasks are completed.
  RunLoop.main.run()
}

main()
