import SwiftUI

@Observable
final class TabOrderManager {
    static let shared = TabOrderManager()

    /// The ordered list of tabs the user wants to see
    var orderedTabs: [ResultTab] {
        get {
            if let saved = UserDefaults.standard.array(forKey: "tabOrder") as? [Int] {
                let tabs = saved.compactMap { ResultTab(rawValue: $0) }
                if tabs.count == ResultTab.allCases.count {
                    return tabs
                }
            }
            return ResultTab.allCases
        }
        set {
            UserDefaults.standard.set(newValue.map { $0.rawValue }, forKey: "tabOrder")
        }
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        var tabs = orderedTabs
        tabs.move(fromOffsets: source, toOffset: destination)
        orderedTabs = tabs
    }

    func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: "tabOrder")
    }

    private init() {}
}
