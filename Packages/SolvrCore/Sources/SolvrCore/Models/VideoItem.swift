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

    // There is deliberately no thumbnail URL here any more.
    //
    // This used to build https://img.youtube.com/vi/<id>/mqdefault.jpg, which the
    // Videos tab fetched automatically on appear -- an unannounced request to
    // Google every time the user opened a tab, in an app that otherwise sends
    // nothing anywhere. `thumbnailURL` is still decoded because it is part of the
    // wire shape, but nothing loads it.
    //
    // Little is lost: the on-device model is asked for *search queries* rather
    // than video IDs, precisely because a model with no network invents IDs that
    // 404 -- so for the backend the app actually ships there was rarely an ID to
    // build a thumbnail from in the first place.
}
