import Foundation

/// Client for Open Food Facts.
/// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
/// Data is published under the Open Database License (ODbL) — attribution is
/// required wherever it's shown to the user (see ProductDetailView footer).
final class OpenFoodFactsService {

    static let shared = OpenFoodFactsService()
    private let baseURL = "https://world.openfoodfacts.org/api/v2"
    private let session = URLSession.shared

    // Open Food Facts blocks requests carrying the default CFNetwork User-Agent
    // with a 503 HTML page (their anti-abuse measure) — their API docs require
    // a descriptive one identifying the app instead.
    private static let userAgent = "SafeBite - iOS - Version 1.0 - https://github.com/vibecoding/ProductScanner"

    private static let fields = [
        "code", "product_name", "brands", "image_url", "ingredients_text",
        "ingredients_text_en", "allergens_tags", "traces_tags", "nova_group",
        "nutriscore_grade", "nutriscore_score", "additives_tags", "labels_tags",
        "nutriments"
    ].joined(separator: ",")

    enum ServiceError: Error {
        case notFound
        case invalidResponse
        case network(Error)
    }

    /// Look up a product by barcode (EAN/UPC).
    func fetchProduct(barcode: String) async throws -> Product {
        guard let url = URL(string: "\(baseURL)/product/\(barcode).json?fields=\(Self.fields)") else {
            throw ServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard decoded.status == 1, let offProduct = decoded.product else {
            throw ServiceError.notFound
        }

        return map(offProduct, source: .barcode)
    }

    /// Search a product by name — used as a fallback when there's no barcode
    /// in frame but the label text was read via OCR.
    func searchProduct(byName name: String) async throws -> Product {
        guard var components = URLComponents(string: "\(baseURL.replacingOccurrences(of: "/api/v2", with: ""))/cgi/search.pl") else {
            throw ServiceError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: name),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "1")
        ]
        guard let url = components.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        // OFF's legacy cgi/search.pl endpoint intermittently answers with a
        // 503 HTML "temporarily unavailable" page (~40% of calls observed) —
        // a short retry smooths over that instead of failing the whole scan.
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw ServiceError.invalidResponse
                }
                let decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
                guard let first = decoded.products.first else { throw ServiceError.notFound }
                return map(first, source: .visualRecognition)
            } catch ServiceError.notFound {
                throw ServiceError.notFound
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        throw lastError ?? ServiceError.invalidResponse
    }

    // MARK: - Map OFF response to our model

    private func map(_ off: OFFProduct, source: Product.ProductSource) -> Product {
        func allergens(from tags: [String]?) -> [Allergen] {
            (tags ?? []).compactMap { tag in
                // Tags are "<lang>:<id>" — OFF doesn't always use "en:" as the
                // prefix (contributors in other locales produce "fr:gluten",
                // "de:gluten", etc. with the same canonical id after the colon).
                // Stripping only the literal "en:" silently dropped every
                // allergen tagged under another language, which is how a
                // gluten-containing product could come back looking "safe".
                let id = tag.split(separator: ":").last.map(String.init) ?? tag
                return Allergen(rawValue: id)
            }
        }

        let ingredients = off.ingredientsTextEN?.isEmpty == false ? off.ingredientsTextEN : off.ingredientsText

        // allergens_tags is contributor-filled and often left blank even when
        // the ingredient list clearly names a dairy/gluten/etc. ingredient (a
        // real product hit this: "organic cream" with empty allergens_tags).
        // Keyword-scanning the ingredient text the same way the OCR fallback
        // does catches what the structured field misses.
        let keywordAllergens = Set(TextRecognitionService.shared.detectAllergens(inText: ingredients ?? ""))
        let contains = Array(Set(allergens(from: off.allergensTags)).union(keywordAllergens))
        // "May contain traces of" — cross-contact warning. Ignoring this field
        // is what causes a product to be shown as "safe" when the label itself
        // warns about shared-line contamination.
        let traces = Array(Set(allergens(from: off.tracesTags)).subtracting(contains))

        let grade: QualityGrade = {
            switch off.nutriscoreGrade?.lowercased() {
            case "a": return .a
            case "b": return .b
            case "c": return .c
            case "d": return .d
            case "e": return .e
            default: return .unknown
            }
        }()

        // Additives: OFF tags look like "en:e330". Deduplicate by normalized code.
        let additives: [Additive] = {
            let looked = (off.additivesTags ?? []).map { AdditiveDatabase.lookup(tag: $0) }
            var seen = Set<String>()
            return looked.filter { seen.insert($0.code).inserted }
        }()

        // Organic: any label tag mentioning an organic certification.
        let isOrganic = (off.labelsTags ?? []).contains { tag in
            let t = tag.lowercased()
            return t.contains("organic") || t.contains("bio") || t.contains("ecocert")
        }

        let healthScore = ProductScoreService.score(
            nutriScore: off.nutriscoreScore,
            grade: grade,
            additives: additives,
            isOrganic: isOrganic
        )

        return Product(
            id: off.code ?? UUID().uuidString,
            name: off.productName ?? "Unknown product",
            brand: off.brands,
            imageURL: URL(string: off.imageUrl ?? ""),
            ingredientsText: ingredients,
            allergens: contains,
            traceAllergens: traces,
            qualityGrade: grade,
            novaGroup: off.novaGroup,
            nutriments: off.nutriments?.mapped,
            additives: additives,
            isOrganic: isOrganic,
            healthScore: healthScore,
            source: source
        )
    }
}

// MARK: - DTOs for the Open Food Facts response

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

private struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let imageUrl: String?
    let ingredientsText: String?
    let ingredientsTextEN: String?
    let allergensTags: [String]?
    let tracesTags: [String]?
    let novaGroup: Int?
    let nutriscoreGrade: String?
    let nutriscoreScore: Double?
    let additivesTags: [String]?
    let labelsTags: [String]?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case imageUrl = "image_url"
        case ingredientsText = "ingredients_text"
        case ingredientsTextEN = "ingredients_text_en"
        case allergensTags = "allergens_tags"
        case tracesTags = "traces_tags"
        case novaGroup = "nova_group"
        case nutriscoreGrade = "nutriscore_grade"
        case nutriscoreScore = "nutriscore_score"
        case additivesTags = "additives_tags"
        case labelsTags = "labels_tags"
        case nutriments
    }
}

private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let fat100g: Double?
    let saturatedFat100g: Double?
    let carbohydrates100g: Double?
    let sugars100g: Double?
    let fiber100g: Double?
    let proteins100g: Double?
    let salt100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case fat100g = "fat_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case sugars100g = "sugars_100g"
        case fiber100g = "fiber_100g"
        case proteins100g = "proteins_100g"
        case salt100g = "salt_100g"
    }

    var mapped: Nutriments {
        Nutriments(
            energyKcal: energyKcal100g,
            fat: fat100g,
            saturatedFat: saturatedFat100g,
            carbohydrates: carbohydrates100g,
            sugars: sugars100g,
            fiber: fiber100g,
            proteins: proteins100g,
            salt: salt100g
        )
    }
}
