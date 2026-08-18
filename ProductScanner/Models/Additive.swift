import Foundation

// MARK: - Additive risk level
// Risk tiers mirror the way Yuka communicates additive hazard: from harmless
// to best-avoided. Ratings are a curated distillation of EFSA / ANSES / IARC
// positions on the most common food additives sold in the US and EU. This is
// intentionally conservative and not medical advice.
enum AdditiveRisk: Int, Codable, Comparable {
    case riskFree = 0     // no known concern (citric acid, pectin, vitamin C…)
    case limited  = 1     // low concern, fine in normal amounts
    case moderate = 2     // some concern / debated evidence
    case high     = 3     // best avoided (azo dyes, nitrites, BHA/BHT…)

    static func < (lhs: AdditiveRisk, rhs: AdditiveRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .riskFree: return "No risk"
        case .limited:  return "Limited risk"
        case .moderate: return "Moderate risk"
        case .high:     return "Hazardous"
        }
    }

    var colorName: String {
        switch self {
        case .riskFree: return "green"
        case .limited:  return "mint"
        case .moderate: return "orange"
        case .high:     return "red"
        }
    }
}

// MARK: - A single additive detected on the product
struct Additive: Identifiable, Codable, Hashable {
    let code: String        // normalized E-number, e.g. "E330"
    let risk: AdditiveRisk
    let name: String?       // human-readable name when we know it

    var id: String { code }

    var displayName: String {
        if let name { return "\(code) · \(name)" }
        return code
    }
}

// MARK: - Additive risk database
// Keyed by normalized E-number. Anything not listed is treated as unrated and
// carries no scoring penalty (see ProductScoreService), but is still shown.
enum AdditiveDatabase {

    /// Normalize an Open Food Facts additive tag ("en:e330", "e330i", "E 330")
    /// into a canonical "E330" key.
    static func normalize(tag: String) -> String {
        var s = tag.lowercased()
        if let range = s.range(of: "en:") { s.removeSubrange(range) }
        s = s.replacingOccurrences(of: " ", with: "")
        // Drop sub-variant suffixes like "e330i" / "e150d" -> "e330" / "e150"
        // by keeping the leading "e" + digits.
        guard s.hasPrefix("e") else { return tag.uppercased() }
        let digits = s.dropFirst().prefix { $0.isNumber }
        guard !digits.isEmpty else { return tag.uppercased() }
        return "E\(digits)"
    }

    static func lookup(tag: String) -> Additive {
        let code = normalize(tag: tag)
        let entry = table[code]
        return Additive(code: code, risk: entry?.risk ?? .limited, name: entry?.name)
    }

    private struct Entry { let risk: AdditiveRisk; let name: String? }

    // Data is kept as flat (code, name) arrays per risk tier. A single large
    // dictionary literal of `Entry(...)` values makes the Swift type-checker
    // pathologically slow (tens of seconds); homogeneous string-tuple arrays
    // type-check almost instantly, and we assemble the lookup dictionary once.
    private static let table: [String: Entry] = {
        var t = [String: Entry](minimumCapacity: 96)
        for (code, name) in highRisk    { t[code] = Entry(risk: .high,     name: name) }
        for (code, name) in moderateRisk { t[code] = Entry(risk: .moderate, name: name) }
        for (code, name) in limitedRisk  { t[code] = Entry(risk: .limited,  name: name) }
        for (code, name) in riskFree     { t[code] = Entry(risk: .riskFree, name: name) }
        return t
    }()

    // Curated subset covering the additives that appear on the vast majority of
    // US/EU packaged foods. Default for anything unlisted is `.limited`.

    private static let highRisk: [(String, String)] = [
        ("E102", "Tartrazine"), ("E104", "Quinoline Yellow"), ("E110", "Sunset Yellow"),
        ("E122", "Azorubine"), ("E124", "Ponceau 4R"), ("E127", "Erythrosine"),
        ("E129", "Allura Red"), ("E131", "Patent Blue V"), ("E142", "Green S"),
        ("E151", "Brilliant Black BN"), ("E154", "Brown FK"), ("E155", "Brown HT"),
        ("E171", "Titanium Dioxide"), ("E210", "Benzoic acid"), ("E249", "Potassium nitrite"),
        ("E250", "Sodium nitrite"), ("E251", "Sodium nitrate"), ("E252", "Potassium nitrate"),
        ("E320", "BHA"), ("E321", "BHT"), ("E952", "Cyclamate"),
    ]

    private static let moderateRisk: [(String, String)] = [
        ("E133", "Brilliant Blue FCF"), ("E150", "Caramel colour"), ("E173", "Aluminium"),
        ("E180", "Litholrubine BK"), ("E211", "Sodium benzoate"), ("E212", "Potassium benzoate"),
        ("E213", "Calcium benzoate"), ("E220", "Sulphur dioxide"), ("E221", "Sodium sulphite"),
        ("E222", "Sodium bisulphite"), ("E223", "Sodium metabisulphite"),
        ("E224", "Potassium metabisulphite"), ("E310", "Propyl gallate"), ("E319", "TBHQ"),
        ("E338", "Phosphoric acid"), ("E339", "Sodium phosphates"), ("E340", "Potassium phosphates"),
        ("E385", "Calcium disodium EDTA"), ("E407", "Carrageenan"), ("E450", "Diphosphates"),
        ("E451", "Triphosphates"), ("E452", "Polyphosphates"), ("E466", "Carboxymethyl cellulose"),
        ("E621", "Monosodium glutamate"), ("E951", "Aspartame"), ("E954", "Saccharin"),
    ]

    private static let limitedRisk: [(String, String)] = [
        ("E200", "Sorbic acid"), ("E202", "Potassium sorbate"), ("E412", "Guar gum"),
        ("E415", "Xanthan gum"), ("E420", "Sorbitol"), ("E471", "Mono- and diglycerides"),
        ("E472", "Fatty acid esters"), ("E950", "Acesulfame K"), ("E955", "Sucralose"),
        ("E960", "Steviol glycosides"),
    ]

    private static let riskFree: [(String, String)] = [
        ("E100", "Curcumin"), ("E101", "Riboflavin"), ("E160", "Carotenes"),
        ("E162", "Beetroot Red"), ("E163", "Anthocyanins"), ("E170", "Calcium carbonate"),
        ("E260", "Acetic acid"), ("E270", "Lactic acid"), ("E290", "Carbon dioxide"),
        ("E296", "Malic acid"), ("E300", "Ascorbic acid (Vit C)"), ("E301", "Sodium ascorbate"),
        ("E306", "Tocopherols (Vit E)"), ("E322", "Lecithins"), ("E325", "Sodium lactate"),
        ("E330", "Citric acid"), ("E331", "Sodium citrates"), ("E332", "Potassium citrates"),
        ("E333", "Calcium citrates"), ("E334", "Tartaric acid"), ("E336", "Potassium tartrate"),
        ("E401", "Sodium alginate"), ("E406", "Agar"), ("E410", "Locust bean gum"),
        ("E414", "Acacia gum"), ("E422", "Glycerol"), ("E440", "Pectin"),
        ("E500", "Sodium carbonates"), ("E501", "Potassium carbonates"),
        ("E503", "Ammonium carbonates"), ("E504", "Magnesium carbonates"),
        ("E509", "Calcium chloride"), ("E575", "Glucono-delta-lactone"),
    ]
}
