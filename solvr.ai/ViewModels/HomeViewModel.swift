import SwiftUI

@Observable
final class HomeViewModel {

    var problemText: String = ""
    var errorMessage: String?

    let topics = ["Algebra", "Calculus", "Geometry", "Statistics", "Trig", "Linear Algebra"]

    let sampleProblems: [String: String] = [
        "Algebra": "Solve for x: 3x\u{00B2} + 7x - 6 = 0",
        "Calculus": "Find the derivative of f(x) = x\u{00B3} \u{00B7} sin(x)",
        "Geometry": "Find the area of a triangle with sides 5, 12, and 13",
        "Statistics": "Find the standard deviation of the data set: {4, 8, 15, 16, 23, 42}",
        "Trig": "Solve for \u{03B8}: 2sin(\u{03B8}) - 1 = 0, where 0 \u{2264} \u{03B8} \u{2264} 2\u{03C0}",
        "Linear Algebra": "Find the determinant of the matrix [[3, 1], [5, 2]]",
    ]

    func selectTopic(_ topic: String) {
        if let sample = sampleProblems[topic] {
            withAnimation(Theme.Animation.standard) {
                problemText = sample
            }
            Haptics.selection()
        }
    }
}
