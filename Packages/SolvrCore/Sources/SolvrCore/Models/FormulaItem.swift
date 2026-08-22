import Foundation

/// A formula relevant to a problem.
///
/// Lenient on decode: a missing field becomes a placeholder rather than failing
/// the whole array, because one malformed entry in six should not cost the user
/// the other five.
public struct FormulaItem: Codable, Identifiable, Sendable {
    /// Derived from the content, not from `name`. Models repeat names.
    public var id: String { "\(name)|\(formula)" }
    public let name: String
    public let formula: String
    public let description: String

    public init(name: String, formula: String, description: String) {
        self.name = name
        self.formula = formula
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Formula"
        formula = (try? container.decode(String.self, forKey: .formula)) ?? ""
        description = (try? container.decode(String.self, forKey: .description)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name, formula, description
    }
}
