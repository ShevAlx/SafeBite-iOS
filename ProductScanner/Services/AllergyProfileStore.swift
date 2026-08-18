import Foundation

/// Persists the user's allergen preferences across launches via UserDefaults.
enum AllergyProfileStore {
    private static let key = "userAllergyProfile"

    static func load() -> Set<Allergen> {
        let rawValues = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(rawValues.compactMap(Allergen.init(rawValue:)))
    }

    static func save(_ profile: Set<Allergen>) {
        UserDefaults.standard.set(profile.map(\.rawValue), forKey: key)
    }
}
