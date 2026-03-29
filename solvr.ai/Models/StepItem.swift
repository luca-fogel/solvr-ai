import Foundation

struct StepItem: Codable, Identifiable {
    var id: Int { step }
    let step: Int
    let title: String
    let explanation: String
    let math: String?

    init(step: Int, title: String, explanation: String, math: String?) {
        self.step = step
        self.title = title
        self.explanation = explanation
        self.math = math
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = (try? container.decode(Int.self, forKey: .step)) ?? 1
        title = (try? container.decode(String.self, forKey: .title)) ?? "Step"
        explanation = (try? container.decode(String.self, forKey: .explanation)) ?? ""
        math = try? container.decodeIfPresent(String.self, forKey: .math)
    }

    private enum CodingKeys: String, CodingKey {
        case step, title, explanation, math
    }
}
