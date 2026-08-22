import SwiftUI
import PhotosUI
import SolvrCore

enum ScannerState: Equatable {
    case camera
    case detecting
    case selection
    case preview
}

@Observable
final class ScannerViewModel {

    var state: ScannerState = .camera
    var capturedImage: UIImage?
    var detectedProblems: [DetectedProblem] = []
    var selectedProblem: DetectedProblem?
    var errorMessage: String?

    private let api = AnthropicProvider()

    // MARK: - Capture

    func capturePhoto(from cameraManager: CameraManager) {
        guard let image = cameraManager.captureCurrentFrame() else {
            errorMessage = "Could not capture image. Try again."
            return
        }
        capturedImage = image
        state = .detecting
        Haptics.medium()
        detectProblems()
    }

    func usePhotoLibraryImage(_ image: UIImage) {
        capturedImage = image
        state = .detecting
        Haptics.medium()
        detectProblems()
    }

    // MARK: - Detection

    private func detectProblems() {
        guard let image = capturedImage else { return }
        errorMessage = nil

        Task {
            do {
                let rawProblems = try await api.detectProblems(in: image)
                let validated = Self.validateBoundingBoxes(rawProblems)
                let problems = Self.filterDetectedProblems(validated)
                await MainActor.run {
                    detectedProblems = problems
                    if problems.isEmpty {
                        errorMessage = "No math problems detected. Try a clearer photo."
                        state = .camera
                    } else {
                        state = .selection
                        Haptics.success()
                    }
                }
            } catch {
                await MainActor.run {
                    let claudeError = error as? SolverError
                    errorMessage = claudeError?.errorDescription ?? error.localizedDescription
                    state = .camera
                    Haptics.medium()
                }
            }
        }
    }

    // MARK: - Selection

    func selectProblem(_ problem: DetectedProblem) {
        selectedProblem = problem
        state = .preview
        Haptics.light()
    }

    // MARK: - Navigation

    func retake() {
        capturedImage = nil
        detectedProblems = []
        selectedProblem = nil
        errorMessage = nil
        state = .camera
    }

    func backToSelection() {
        selectedProblem = nil
        state = .selection
    }

    // MARK: - Bounding Box Validation

    /// Cap individual box height — a single problem rarely takes more than 12% of the image.
    private static func validateBoundingBoxes(_ problems: [DetectedProblem]) -> [DetectedProblem] {
        problems.map { p in
            if p.bbox.height > 12 {
                return DetectedProblem(
                    bbox: .init(top: p.bbox.top, left: p.bbox.left, width: p.bbox.width, height: 12),
                    latex: p.latex
                )
            }
            return p
        }
    }

    // MARK: - Post-Processing Filter

    private static func filterDetectedProblems(_ problems: [DetectedProblem]) -> [DetectedProblem] {
        problems.filter { p in
            let latex = p.latex.trimmingCharacters(in: .whitespacesAndNewlines)

            // Must have actual LaTeX content
            guard !latex.isEmpty else { return false }

            // Must have math indicators — at least one LaTeX command, operator, or math symbol
            let hasMath = latex.contains("\\") ||
                          latex.contains("^") ||
                          latex.contains("_") ||
                          latex.contains("=") ||
                          latex.contains("+") ||
                          latex.contains("-")
            guard hasMath else { return false }

            // Filter out obvious non-math detections
            let lower = latex.lowercased()
            let nonMathKeywords = ["pdf", "practice", "midterm", "download", "file",
                                   "kb)", "100%", "page", ".pdf", "spring 20", "fall 20",
                                   "sec ", "bos-", "canvas"]
            for keyword in nonMathKeywords {
                if lower.contains(keyword) { return false }
            }

            // Box size sanity checks
            guard p.bbox.width > 10 else { return false }
            guard p.bbox.height > 2 else { return false }
            guard p.bbox.width * p.bbox.height < 3000 else { return false }

            // Remove boxes near the very top or bottom (likely UI elements)
            guard p.bbox.top > 2 && (p.bbox.top + p.bbox.height) < 98 else { return false }

            return true
        }
    }

    // MARK: - Cropped Image

    func croppedImage(for problem: DetectedProblem) -> UIImage? {
        guard let image = capturedImage else { return nil }
        let imgW = image.size.width
        let imgH = image.size.height
        let bbox = problem.bbox

        // Minimal padding — just 1% horizontal, 0.5% vertical
        let padX: Double = 1.0
        let padY: Double = 0.5
        let cropX = max(0, (bbox.left - padX) / 100.0 * imgW)
        let cropY = max(0, (bbox.top - padY) / 100.0 * imgH)
        let cropW = min(imgW - cropX, (bbox.width + padX * 2) / 100.0 * imgW)
        let cropH = min(imgH - cropY, (bbox.height + padY * 2) / 100.0 * imgH)

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
