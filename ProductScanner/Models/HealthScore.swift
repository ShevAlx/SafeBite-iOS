import Foundation

// MARK: - Overall product health score (0–100), Yuka-style
// A single number the user can read at a glance, plus the breakdown that
// produced it so the score is explainable rather than a black box.
struct HealthScore: Codable {
    let total: Int                  // 0–100
    let nutrition: Int              // 0–60 contribution
    let additives: Int              // 0–30 contribution
    let organicBonus: Int           // 0–10 contribution

    var category: Category { Category(total: total) }

    enum Category: String, Codable {
        case excellent  // 75–100
        case good       // 50–74
        case poor       // 25–49
        case bad        // 0–24

        init(total: Int) {
            switch total {
            case 75...:  self = .excellent
            case 50..<75: self = .good
            case 25..<50: self = .poor
            default:      self = .bad
            }
        }

        var label: String {
            switch self {
            case .excellent: return "Excellent"
            case .good:      return "Good"
            case .poor:      return "Poor"
            case .bad:       return "Bad"
            }
        }

        var colorName: String {
            switch self {
            case .excellent: return "green"
            case .good:      return "mint"
            case .poor:      return "orange"
            case .bad:       return "red"
            }
        }
    }
}
