import Vision
import UIKit
import SolvrCore

/// On-device text recognition. Vision, no network, no model download.
///
/// This is the only thing between a photograph and a question, and it runs
/// exactly once per solve -- `SolveBuilder` calls it while the `Solve` is being
/// constructed, before any surface exists to be asked for. It used to run
/// underneath the provider, once per surface, and what it read was never shown
/// to anyone.
///
/// The trade it makes is real and worth stating: Apple's on-device model accepts
/// no image input at all, so a photograph has to become text before it can be
/// asked about, and text recognition reads a fraction as two numbers with a line
/// between them where a vision model would read a fraction. That is why the app
/// now puts the recognised text on screen under the photograph. A misread is the
/// most likely thing to go wrong on this path, and the student is the only one
/// who can see that it has.
enum OCRService {

    static func recognizeText(from image: UIImage) async throws -> String {
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
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            // On for prose, and it is prose this has to read too -- the word
            // problem wrapped around the equation.
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
