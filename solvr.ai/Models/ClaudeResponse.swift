import Foundation

// MARK: - Claude API Request/Response

// Text-only request (existing flow)
struct ClaudeRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
    let system: String?
    
    init(model: String = "claude-sonnet-4-6", maxTokens: Int = 1024, messages: [ClaudeMessage], system: String? = nil) {
        self.model = model
        self.max_tokens = maxTokens
        self.messages = messages
        self.system = system
    }
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

// Multimodal request (image + text)
struct ClaudeMultiModalRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [MultiModalMessage]
    let system: String?

    struct MultiModalMessage: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    struct ContentBlock: Encodable {
        let type: String
        let text: String?
        let source: ImageSource?

        init(text: String) {
            self.type = "text"
            self.text = text
            self.source = nil
        }

        init(imageData: String, mediaType: String = "image/jpeg") {
            self.type = "image"
            self.text = nil
            self.source = ImageSource(type: "base64", media_type: mediaType, data: imageData)
        }
    }

    struct ImageSource: Encodable {
        let type: String
        let media_type: String
        let data: String
    }
}

// Response (same for text and multimodal)
struct ClaudeAPIResponse: Codable {
    let id: String?
    let content: [ContentBlock]?
    let error: APIError?
    
    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
    
    struct APIError: Codable {
        let type: String?
        let message: String?
    }
    
    var text: String? {
        content?.first(where: { $0.type == "text" })?.text
    }
}

// MARK: - Video Model

struct VideoItem: Codable, Identifiable {
    var id: String { title + channel }
    let title: String
    let channel: String
    let searchQuery: String
    let videoId: String?
    let thumbnailURL: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        channel = try container.decode(String.self, forKey: .channel)
        searchQuery = try container.decode(String.self, forKey: .searchQuery)
        videoId = try container.decodeIfPresent(String.self, forKey: .videoId)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
    }

    var youtubeURL: URL? {
        if let videoId, !videoId.isEmpty {
            return URL(string: "https://www.youtube.com/watch?v=\(videoId)")
        }
        let query = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.youtube.com/results?search_query=\(query)")
    }

    var thumbnailImageURL: URL? {
        if let videoId, !videoId.isEmpty {
            return URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")
        }
        if let thumbnailURL, let url = URL(string: thumbnailURL) {
            return url
        }
        return nil
    }
}
