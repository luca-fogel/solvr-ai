import Foundation

/// The Messages API wire format, built as dictionaries rather than `Codable`
/// structs.
///
/// A request body is a wire format, not a domain type, and the structured-output
/// variant needs to embed an arbitrary JSON Schema -- which `Codable` makes
/// tedious and `JSONSerialization` makes trivial. One builder for every shape is
/// easier to read than two that diverge.
enum AnthropicWire {

    static func requestBody(model: String,
                            maxTokens: Int,
                            prompt: String,
                            imageJPEG: Data?,
                            system: String?,
                            history: [(role: String, content: String)],
                            schema: JSONSchema?) throws -> Data {
        var messages: [[String: Any]] = history.map {
            ["role": $0.role, "content": $0.content]
        }

        if let imageJPEG {
            // Anthropic's own image envelope. An OpenAI-compatible endpoint uses
            // `image_url` with a data URI instead, which is why this belongs to
            // the provider rather than to a shared request type.
            messages.append([
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64",
                                "media_type": "image/jpeg",
                                "data": imageJPEG.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ])
        } else {
            messages.append(["role": "user", "content": prompt])
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages,
        ]
        if let system { body["system"] = system }
        if let schema {
            body["output_config"] = [
                "format": ["type": "json_schema", "schema": schema.object]
            ]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    struct Response {
        let text: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let errorMessage: String?

        init(data: Data) {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let blocks = root?["content"] as? [[String: Any]]
            text = blocks?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            let usage = root?["usage"] as? [String: Any]
            inputTokens = usage?["input_tokens"] as? Int
            outputTokens = usage?["output_tokens"] as? Int
            errorMessage = (root?["error"] as? [String: Any])?["message"] as? String
        }
    }
}

/// A JSON Schema for `output_config.format`.
///
/// The API guarantees a response that validates against this, which is the whole
/// point: it moves schema compliance from something the prompt asks for to
/// something the decoder enforces. Note the array surfaces are wrapped in an
/// object with a single `items` property -- a bare array at the root is not
/// reliably accepted, and wrapping costs one unwrap.
// `@unchecked` because the payload is an untyped JSON tree. It is built once
// from literals and never mutated, which is the invariant the checker cannot see.
public struct JSONSchema: @unchecked Sendable {
    let object: [String: Any]
    /// Property to unwrap after decoding, for the array surfaces.
    let unwrapKey: String?

    static func objectSchema(properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object",
         "properties": properties,
         "required": required,
         "additionalProperties": false]
    }

    // Computed rather than stored: an untyped JSON tree cannot be a global
    // constant under strict concurrency checking, and these are cheap literals.
    private static var string: [String: Any] { ["type": "string"] }
    private static var nullableString: [String: Any] { ["type": ["string", "null"]] }

    public static let lesson = JSONSchema(
        object: objectSchema(
            properties: [
                "title": string,
                "topic": string,
                "introduction": string,
                "keyTakeaway": nullableString,
                "sections": [
                    "type": "array",
                    "items": objectSchema(
                        properties: [
                            "heading": string,
                            "content": string,
                            "formula": nullableString,
                            "note": nullableString,
                            "steps": ["type": ["array", "null"], "items": string],
                        ],
                        required: ["heading", "content", "formula", "note", "steps"]),
                ],
            ],
            required: ["title", "topic", "introduction", "sections", "keyTakeaway"]),
        unwrapKey: nil)

    public static let steps = wrapped(
        objectSchema(properties: [
            "step": ["type": "integer"],
            "title": string,
            "explanation": string,
            "math": nullableString,
        ], required: ["step", "title", "explanation", "math"]))

    public static let formulas = wrapped(
        objectSchema(properties: [
            "name": string,
            "formula": string,
            "description": string,
        ], required: ["name", "formula", "description"]))

    public static let videos = wrapped(
        objectSchema(properties: [
            "title": string,
            "channel": string,
            "searchQuery": string,
            "videoId": nullableString,
            "thumbnailURL": nullableString,
        ], required: ["title", "channel", "searchQuery", "videoId", "thumbnailURL"]))

    private static func wrapped(_ element: [String: Any]) -> JSONSchema {
        JSONSchema(
            object: objectSchema(
                properties: ["items": ["type": "array", "items": element]],
                required: ["items"]),
            unwrapKey: "items")
    }
}
