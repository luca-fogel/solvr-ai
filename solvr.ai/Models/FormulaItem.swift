import Foundation

struct FormulaItem: Codable, Identifiable {
    var id: String { name }
    let name: String
    let formula: String
    let description: String

    init(name: String, formula: String, description: String) {
        self.name = name
        self.formula = formula
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Formula"
        formula = (try? container.decode(String.self, forKey: .formula)) ?? ""
        description = (try? container.decode(String.self, forKey: .description)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name, formula, description
    }
}
