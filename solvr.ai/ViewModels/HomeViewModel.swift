import SwiftUI
import SolvrCore

@Observable
final class HomeViewModel {

    var problemText: String = ""
    var errorMessage: String?

    // The chips and their problems live in `SolvrCore.SampleProblems`, which the
    // evaluation harness also links. Duplicating the strings here would mean the
    // measured text and the tapped text could drift apart, and the drift would
    // be invisible until a student hit it.
    let topics = SampleProblems.topics

    let sampleProblems: [String: String] = SampleProblems.byTopic

    func selectTopic(_ topic: String) {
        if let sample = sampleProblems[topic] {
            withAnimation(Theme.Animation.standard) {
                problemText = sample
            }
            Haptics.selection()
        }
    }
}
