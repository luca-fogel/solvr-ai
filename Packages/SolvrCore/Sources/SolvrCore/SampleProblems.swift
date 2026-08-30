import Foundation

/// The problems the topic chips insert, and the answers they should produce.
///
/// These used to be six string literals in `HomeViewModel` and nowhere else,
/// which made them the least tested strings in the app and the first six a
/// student ever taps. They are also the strings most likely to expose a
/// notation bug: between them they carry `²`, `³`, `·`, `θ`, `≤` and `π`, and
/// how the model handles `x³` is not how it handles `x^3`.
///
/// So they live here, in the package the evaluation harness links, and the app
/// reads them from here. The harness can then run *byte-identical* text --
/// `solvr-eval --backend on-device --set samples` -- and a claim about "the
/// examples work" is a graded run rather than a memory of tapping one.
public struct SampleProblem: Sendable, Hashable {

    /// Stable across reruns so two graded runs can be diffed by problem.
    public let id: String

    /// The chip label, and the order the chips appear in.
    public let topic: String

    /// Exactly what the chip puts in the text field. Not "roughly" -- the
    /// harness measures this string.
    public let text: String

    /// The correct answer, for the grader. Written the way a marker would,
    /// not the way the model happens to phrase it: `grade_answers.py` compares
    /// symbolically, so `2/3` and `\frac{2}{3}` are one answer.
    public let expectedAnswer: String

    /// Present only when the answer is a single real number, which is the case
    /// the grader can decide numerically.
    public let expectedNumeric: Double?

    public init(id: String, topic: String, text: String,
                expectedAnswer: String, expectedNumeric: Double? = nil) {
        self.id = id
        self.topic = topic
        self.text = text
        self.expectedAnswer = expectedAnswer
        self.expectedNumeric = expectedNumeric
    }
}

public enum SampleProblems {

    /// Ordered as the chips are ordered.
    public static let all: [SampleProblem] = [
        // Was `3x² + 7x - 6 = 0`, which the model solved by the quadratic
        // formula and then slipped on the arithmetic -- `4/6 = 1/3` -- in a run
        // that looked entirely confident. Measured, replaced.
        SampleProblem(
            id: "sam-alg-01",
            topic: "Algebra",
            text: "Solve for x: x\u{00B2} - 5x + 6 = 0",
            expectedAnswer: "x = 2 or x = 3"),
        SampleProblem(
            id: "sam-cal-01",
            topic: "Calculus",
            text: "Find the derivative of f(x) = x\u{00B3} \u{00B7} sin(x)",
            // Written in sympy's syntax, because that is what grades it:
            // `3x^2 sin(x)` parses as a product of the letters s, i and n.
            expectedAnswer: "3*x**2*sin(x) + x**3*cos(x)"),
        SampleProblem(
            id: "sam-geo-01",
            topic: "Geometry",
            text: "Find the area of a triangle with sides 5, 12, and 13",
            expectedAnswer: "30",
            expectedNumeric: 30),
        // Standard deviation is out of this model's reach, and not marginally:
        // every phrasing tried -- six values, four values, the textbook
        // {2,4,4,4,5,5,7,9} -- ran past the 4,096-token context window and
        // returned `contextExceeded`, i.e. no answer at all, every time. A chip
        // that always errors is worse than a chip that asks something smaller,
        // so this asks something smaller. The topic is still statistics.
        SampleProblem(
            id: "sam-sta-01",
            topic: "Statistics",
            text: "Find the median of the data set: 3, 7, 7, 2, 9, 4",
            expectedAnswer: "5.5",
            expectedNumeric: 5.5),
        SampleProblem(
            id: "sam-tri-01",
            topic: "Trig",
            text: "Solve for \u{03B8}: 2sin(\u{03B8}) - 1 = 0, "
                + "where 0 \u{2264} \u{03B8} \u{2264} 2\u{03C0}",
            expectedAnswer: "pi/6 or 5*pi/6"),
        SampleProblem(
            id: "sam-lin-01",
            topic: "Linear Algebra",
            text: "Find the determinant of the matrix [[3, 1], [5, 2]]",
            expectedAnswer: "1",
            expectedNumeric: 1),
    ]

    /// The chip labels, in order.
    public static let topics: [String] = all.map(\.topic)

    /// Chip label to the text it inserts.
    public static let byTopic: [String: String] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.topic, $0.text) })
}
