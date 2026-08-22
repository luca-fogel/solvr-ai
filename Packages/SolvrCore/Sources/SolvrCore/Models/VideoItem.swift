import Foundation

/// A suggested video for a topic.
///
/// Strict on `title`, `channel` and `searchQuery` -- without a query there is
/// nothing to link to -- and lenient on `videoId` and `thumbnailURL`, which
/// models supply inconsistently and which `youtubeURL` can work around.
public struct VideoItem: Codable, Identifiable, Sendable {
    /// Derived from all three required fields. `title + channel` collided
    /// whenever a model suggested the same video twice under one channel.
    public var id: String { "\(title)|\(channel)|\(searchQuery)" }
    public let title: String
    public let channel: String
    public let searchQuery: String
    public let videoId: String?
    public let thumbnailURL: String?

    /// The wire format arrives through `init(from:)` below. This exists because a
    /// provider that generates typed values directly -- guided generation on the
    /// on-device model, or a fixture -- had no way to construct a `VideoItem` at
    /// all: the only initialiser was a decoder.
    public init(title: String, channel: String, searchQuery: String,
                videoId: String? = nil, thumbnailURL: String? = nil) {
        self.title = title
        self.channel = channel
        self.searchQuery = searchQuery
        self.videoId = videoId
        self.thumbnailURL = thumbnailURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        channel = try container.decode(String.self, forKey: .channel)
        searchQuery = try container.decode(String.self, forKey: .searchQuery)
        videoId = try container.decodeIfPresent(String.self, forKey: .videoId)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
    }

    public var youtubeURL: URL? {
        if let videoId, !videoId.isEmpty {
            return URL(string: "https://www.youtube.com/watch?v=\(videoId)")
        }
        let query = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.youtube.com/results?search_query=\(query)")
    }

    public var thumbnailImageURL: URL? {
        if let videoId, !videoId.isEmpty {
            return URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")
        }
        if let thumbnailURL, let url = URL(string: thumbnailURL) {
            return url
        }
        return nil
    }
}
