import Foundation

/// One problem, resolved once, before anything is asked about it.
///
/// This type exists because of a photograph of `∫ 3x² + 2x + 4 dx` that produced
/// a lesson about flatbed scanners. The app had four strings in play for one
/// solve -- `"Scanning..."` while the camera closed, `"[Scanned Image]"` in the
/// view model, a model-written title that replaced it a few seconds later, and
/// the text Vision had actually read -- and only the last of those was a
/// question. Three of them reached a prompt anyway, because they were all
/// `String` and any `String` fits where a problem is expected.
///
/// So `question` is the only string in the app that a prompt is ever built from,
/// there is no second string beside it that could be mistaken for one, and both
/// initialisers require it. A label is not a `Solve` and will not compile as one.
///
/// **Resolved once.** For a photograph the recognition happens here, in the
/// constructor, rather than inside a provider on each request. That is what
/// makes "every surface of one solve receives byte-identical input" true by
/// construction rather than by four call sites agreeing -- and it also means
/// Vision runs once instead of five times, and that a photograph nothing can be
/// read from fails before a results screen is ever shown.
public struct Solve: Sendable, Equatable, Identifiable {

    public let id: UUID

    /// Exactly what the model is asked about. The *only* string that reaches a
    /// prompt, and the string the user is shown, so the two cannot disagree.
    public let question: String

    /// Where the question came from. Carried for display and for provenance --
    /// a measurement of a photographed problem and a measurement of a typed one
    /// are not the same measurement.
    public let source: Source

    public enum Source: Sendable, Equatable {
        case typed
        case photograph(jpeg: Data)

        /// Recorded against every measurement, the way `identifier` is.
        public var name: String {
            switch self {
            case .typed: return "typed"
            case .photograph: return "photograph+ocr"
            }
        }
    }

    public init(id: UUID = UUID(), question: String, source: Source) {
        self.id = id
        self.question = question
        self.source = source
    }

    /// The photograph, when there was one.
    public var photograph: Data? {
        if case .photograph(let jpeg) = source { return jpeg }
        return nil
    }

    /// A short form for a list. Display only -- never ask a model about it.
    public var shortLabel: String {
        let single = question.replacingOccurrences(of: "\n", with: " ")
        return single.count <= 60 ? single : String(single.prefix(59)) + "…"
    }
}

/// Turns what the user did into a `Solve`, which is the only way to make one
/// that has a question in it.
///
/// The recogniser is injected rather than imported for the reason `SolvrCore`
/// imports only Foundation: Vision would drag UIKit in with it and the package
/// would stop being runnable by `swift test`, which is most of the reason it
/// exists. The app passes `OCRService`; a test passes a closure.
///
/// This replaces `SightedProvider`, which wrapped a text-only backend so it
/// could be handed a photograph. That was the wrong seam. It put the resolution
/// *below* the four surfaces, so each of them resolved the image separately, the
/// single-entry memo meant to prevent that never hit -- the app builds a new
/// wrapper per request -- and nothing above could see, record, or show what had
/// been read.
public struct SolveBuilder: Sendable {

    /// Photograph bytes in, recognised text out.
    public typealias TextRecogniser = @Sendable (Data) async throws -> String

    private let recognise: TextRecogniser

    public init(recognise: @escaping TextRecogniser) {
        self.recognise = recognise
    }

    public func typed(_ text: String) throws -> Solve {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SolverError.nothingToSolve }
        return Solve(question: trimmed, source: .typed)
    }

    /// Read the photograph, once, and fail here rather than four times later.
    public func photograph(_ jpeg: Data) async throws -> Solve {
        let text: String
        do {
            text = try await recognise(jpeg)
        } catch {
            throw SolverError.decodingFailed(
                context: "image: could not read the text in this photograph")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SolverError.backendUnavailable(
                reason: "No text could be found in that photo. Try a closer, "
                      + "sharper picture, or type the problem instead.")
        }
        return Solve(question: trimmed, source: .photograph(jpeg: jpeg))
    }
}
