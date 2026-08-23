import Vision
import UIKit
import SolvrCore

/// On-device text recognition. Vision, no network, no model download.
///
/// This does two jobs that used to belong to two different places. Reading a
/// photograph into text was always here. *Finding the problems* in a photograph
/// used to be a hosted-vision call -- `AnthropicProvider.detectProblems` sent the
/// JPEG to a model that could see it and asked for bounding boxes back. That
/// backend is gone, and Apple's on-device model cannot replace it: it accepts no
/// image input at all.
///
/// Vision can, and it was already in the app. The trade is real and worth stating:
/// a vision model reads a fraction as a fraction, while OCR reads it as two
/// numbers with a line between them. What Vision gives in exchange is a genuine
/// per-line bounding box, measured rather than described by a model that was
/// asked to estimate coordinates -- which is the part that used to drift.
enum OCRService {

    static func recognizeText(from image: UIImage) async throws -> String {
        try await recognize(image) { observations in
            observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }
    }

    /// Every recognised line that looks like mathematics, with where it sits.
    ///
    /// Deliberately does no grouping: one recognised line is one candidate. The
    /// filters in `ScannerViewModel` then discard the ones that are not problems.
    /// Grouping lines into multi-line problems is the obvious next step and is
    /// not attempted here, because guessing which lines belong together is how
    /// the previous implementation produced boxes that spanned half the page.
    static func detectProblems(from image: UIImage) async throws -> [DetectedProblem] {
        try await recognize(image) { observations in
            observations.compactMap { observation -> DetectedProblem? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !MathNotation.looksLikeProse(trimmed) else { return nil }

                // Vision's boxes are normalised with the origin at the BOTTOM
                // left; every consumer here works in percentages from the TOP
                // left. Getting this wrong flips the crop vertically, which looks
                // like a detection bug rather than a coordinate one.
                let box = observation.boundingBox
                return DetectedProblem(
                    bbox: .init(top: (1 - box.maxY) * 100,
                                left: box.minX * 100,
                                width: box.width * 100,
                                height: box.height * 100),
                    latex: MathNotation.toLaTeX(trimmed))
            }
        }
    }

    private static func recognize<T>(_ image: UIImage,
                                     _ transform: @escaping ([VNRecognizedTextObservation]) -> T
    ) async throws -> T {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: transform(observations))
            }

            request.recognitionLevel = .accurate
            // On for prose, and it is prose this has to read too -- the word
            // problem wrapped around the equation. The maths itself is protected
            // by `looksLikeProse` rejecting whole lines rather than by asking
            // Vision to stop correcting.
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum OCRError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not process the selected image."
            }
        }
    }
}
