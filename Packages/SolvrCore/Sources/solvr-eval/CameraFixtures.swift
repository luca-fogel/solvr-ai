import Foundation
import SolvrCore

#if canImport(Vision)
import Vision
import ImageIO
#endif

/// Photographs with known contents, and what the app should make of them.
///
/// The camera path had never been measured by anything. Every published number
/// in this repository comes from typed text, which is the easier half: the model
/// is the same, but what reaches it is whatever Vision made of a photograph, and
/// nothing recorded that or checked it. This is the missing arm.
///
/// A fixture is a real photograph, taken on the device the app ships to, with
/// its ground truth written down beside it. Two of the fields are unusual and
/// both are deliberate:
///
/// - `expectedText` is what a *correct reading* produces, not what the model
///   should answer. Recognition and solving are separate failures and a run that
///   cannot tell them apart is not worth much.
/// - `expectUnreadable` marks the fixture that must fail. A photograph with
///   nothing legible in it has to produce one honest message before a results
///   screen exists, and a harness that only measures the happy path would never
///   notice if it stopped doing that.
struct CameraFixture: Decodable {
    let id: String
    let file: String
    let topic: String
    /// What Vision should read, if it reads it correctly.
    let expectedText: String
    /// The right answer, for the grader. Written in sympy's syntax.
    let answer: String
    let numeric: Double?
    /// True for the fixture that must be refused rather than solved.
    let expectUnreadable: Bool?
    let notes: String?
}

struct CameraManifest: Decodable {
    let fixtures: [CameraFixture]
}

enum CameraFixtures {

    static func load(from directory: String) -> (dir: URL, fixtures: [CameraFixture]) {
        let dir = URL(fileURLWithPath: directory)
        let manifest = dir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let decoded = try? JSONDecoder().decode(CameraManifest.self, from: data)
        else {
            FileHandle.standardError.write(
                Data("could not read \(manifest.path)\n".utf8))
            exit(1)
        }
        return (dir, decoded.fixtures)
    }

    /// The same `SolveBuilder` the app uses, given macOS Vision.
    ///
    /// Not the same Vision, though, and the difference is the point of the
    /// device arm: this repository has already been caught once believing a Mac
    /// about a phone. What this measures is the pipeline; what the phone
    /// measures is the phone.
    static func builder() -> SolveBuilder {
        SolveBuilder { data in
            #if canImport(Vision)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw SolverError.invalidResponse }

            return try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    continuation.resume(returning: observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: " "))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            #else
            throw SolverError.backendUnavailable(reason: "no Vision on this platform")
            #endif
        }
    }
}
