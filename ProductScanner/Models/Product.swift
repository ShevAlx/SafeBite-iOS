import Foundation

// MARK: - Allergens we recognize
enum Allergen: String, CaseIterable, Identifiable, Codable {
    case milk = "milk"
    case gluten = "gluten"
    case eggs = "eggs"
    case peanuts = "peanuts"
    case nuts = "nuts"
    case soy = "soybeans"
    case fish = "fish"
    case shellfish = "crustaceans"
    case sesame = "sesame-seeds"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .milk: return "Milk"
        case .gluten: return "Gluten"
        case .eggs: return "Eggs"
        case .peanuts: return "Peanuts"
        case .nuts: return "Tree Nuts"
        case .soy: return "Soy"
        case .fish: return "Fish"
        case .shellfish: return "Shellfish"
        case .sesame: return "Sesame"
        }
    }

    var icon: String {
        switch self {
        case .milk: return "🥛"
        case .gluten: return "🌾"
        case .eggs: return "🥚"
        case .peanuts: return "🥜"
        case .nuts: return "🌰"
        case .soy: return "🫘"
        case .fish: return "🐟"
        case .shellfish: return "🦐"
        case .sesame: return "◦"
        }
    }

    // Keywords for the OCR fallback, when the ingredient list is read straight
    // off the label as text instead of arriving structured from the database.
    // Labels are printed in whatever language the product was sold in, so we
    // keep both English and Russian keywords regardless of the app's UI language.
    var ocrKeywords: [String] {
        switch self {
        case .milk: return ["milk", "dairy", "whey", "casein", "lactose", "butter", "cream",
                             "молоко", "молочн", "сыворотк", "казеин", "лактоз", "масло сливочн", "сливк"]
        case .gluten: return ["wheat", "rye", "barley", "oat", "gluten", "flour",
                               "пшениц", "рожь", "ячмень", "овес", "глютен", "мука пшеничн"]
        case .eggs: return ["egg", "albumen", "meringue",
                             "яйцо", "яичн", "меланж"]
        case .peanuts: return ["peanut", "groundnut", "арахис"]
        case .nuts: return ["nut", "almond", "hazelnut", "cashew", "pistachio", "walnut", "pecan",
                             "орех", "миндал", "фундук", "кешью", "фисташ", "грецкий"]
        case .soy: return ["soy", "soya", "soybean", "соя", "соев"]
        case .fish: return ["fish", "anchovy", "salmon", "tuna", "cod",
                             "рыба", "рыбн", "анчоус"]
        case .shellfish: return ["crab", "shrimp", "prawn", "lobster", "crayfish",
                                  "краб", "креветк", "рак"]
        case .sesame: return ["sesame", "tahini", "кунжут"]
        }
    }
}

// MARK: - Product quality grade
enum QualityGrade: String, Codable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case unknown = "?"

    var description: String {
        switch self {
        case .a: return "Excellent quality"
        case .b: return "Good quality"
        case .c: return "Average quality"
        case .d: return "Low quality"
        case .e: return "Very low quality"
        case .unknown: return "No data"
        }
    }

    var colorName: String {
        switch self {
        case .a: return "green"
        case .b: return "mint"
        case .c: return "yellow"
        case .d: return "orange"
        case .e: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Nutrition facts (per 100 g / 100 ml, as reported by the database)
struct Nutriments: Codable {
    var energyKcal: Double?
    var fat: Double?
    var saturatedFat: Double?
    var carbohydrates: Double?
    var sugars: Double?
    var fiber: Double?
    var proteins: Double?
    var salt: Double?

    var isEmpty: Bool {
        energyKcal == nil && fat == nil && saturatedFat == nil && carbohydrates == nil
            && sugars == nil && fiber == nil && proteins == nil && salt == nil
    }
}

// MARK: - Main product model
struct Product: Identifiable, Codable {
    let id: String                  // barcode or generated UUID
    var name: String
    var brand: String?
    var imageURL: URL?
    var ingredientsText: String?
    var allergens: [Allergen]           // explicitly contains
    var traceAllergens: [Allergen]      // "may contain traces of" — cross-contact warning
    var qualityGrade: QualityGrade
    var novaGroup: Int?              // 1-4, degree of food processing
    var nutriments: Nutriments?
    var additives: [Additive]       // E-numbers detected, with risk rating
    var isOrganic: Bool             // carries an organic certification label
    var healthScore: HealthScore?   // computed 0-100 Yuka-style score
    var source: ProductSource

    enum ProductSource: String, Codable {
        case barcode
        case visualRecognition
        case ocrFallback
    }
}
