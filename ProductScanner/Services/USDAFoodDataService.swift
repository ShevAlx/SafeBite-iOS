import Foundation

/// Secondary allergen safety net for barcode scans, queried only when Open
/// Food Facts didn't surface any allergens for a product. OFF's
/// allergens_tags is filled in by contributors and is sometimes left empty
/// even though the same record's ingredient text clearly names an allergen
/// (real example: barcode 742365003837, "organic cream", empty allergens_tags).
/// USDA FoodData Central's Branded Foods dataset is government-sourced and
/// keyed by the same GTIN/UPC, so cross-checking it can catch what OFF's
/// crowd-sourced data missed. This does not protect against OFF returning an
/// internally mismatched record (wrong ingredients tied to the right product
/// name) — cross-referencing a second source by barcode can't detect that.
final class USDAFoodDataService {

    static let shared = USDAFoodDataService()

    private let baseURL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    private let session = URLSession.shared

    /// Returns USDA's on-file ingredient text for this UPC, if it has a
    /// matching Branded Foods record.
    func ingredientsText(forUPC upc: String) async throws -> String? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Secrets.usdaAPIKey),
            URLQueryItem(name: "query", value: upc),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "5")
        ]
        guard let url = components.url else { return nil }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        let normalizedUPC = Self.normalize(upc)
        let match = decoded.foods.first { food in
            guard let gtin = food.gtinUpc else { return false }
            return Self.normalize(gtin) == normalizedUPC
        }
        return match?.ingredients
    }

    /// UPC/EAN barcodes vary in leading-zero padding between databases
    /// (12-digit UPC-A vs. 13-digit EAN-13) — compare on the significant digits.
    private static func normalize(_ code: String) -> String {
        var trimmed = code.drop { $0 == "0" }
        if trimmed.isEmpty { trimmed = code[...] }
        return String(trimmed)
    }
}

private struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    let gtinUpc: String?
    let ingredients: String?
}
