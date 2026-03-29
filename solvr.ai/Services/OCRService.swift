import Vision
import UIKit

enum OCRService {
    
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
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
