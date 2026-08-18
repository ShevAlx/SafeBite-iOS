import Foundation
import UIKit
import SwiftUI

@MainActor
final class ProductScanViewModel: ObservableObject {

    @Published var currentProduct: Product?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// The user's allergies — set on first launch (onboarding) or later in the
    /// profile screen, used to highlight risk. Persisted so it survives relaunch.
    @Published var userAllergyProfile: Set<Allergen> {
        didSet { AllergyProfileStore.save(userAllergyProfile) }
    }

    /// Whether the first-launch onboarding has been completed.
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    private static let onboardingKey = "hasCompletedOnboarding"

    private let offService = OpenFoodFactsService.shared
    private let ocrService = TextRecognitionService.shared
    private let visionService = VisualRecognitionService.shared
    private let usdaService = USDAFoodDataService.shared
    private let successHaptic = UINotificationFeedbackGenerator()

    init() {
        userAllergyProfile = AllergyProfileStore.load()
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    // MARK: - Path 1: by barcode

    func handleBarcode(_ code: String) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                var product = try await offService.fetchProduct(barcode: code)
                if product.allergens.isEmpty {
                    product = await supplementingUSDAAllergens(for: product, barcode: code)
                }
                currentProduct = product
                notifyScanSucceeded()
            } catch OpenFoodFactsService.ServiceError.notFound {
                errorMessage = "Product with barcode \(code) was not found in the database. Try photographing the label instead."
            } catch {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    /// Open Food Facts' allergens_tags is contributor-filled and sometimes
    /// left blank on a record whose own ingredient text clearly names an
    /// allergen. When that happens, cross-check USDA FoodData Central by the
    /// same barcode and keyword-scan its ingredient text as a second opinion.
    private func supplementingUSDAAllergens(for product: Product, barcode: String) async -> Product {
        guard let usdaText = try? await usdaService.ingredientsText(forUPC: barcode),
              !usdaText.isEmpty else {
            return product
        }
        let detected = ocrService.detectAllergens(inText: usdaText)
        guard !detected.isEmpty else { return product }

        var updated = product
        updated.allergens = detected
        return updated
    }

    // MARK: - Path 2: by photo — first visual recognition (Google Vision),
    // falling back to OCR of the ingredient list if that doesn't work.

    func handlePhoto(_ image: UIImage) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            await resolveProduct(from: image)
        }
    }

    private func resolveProduct(from image: UIImage) async {
        // Step 1: try to visually identify the specific product from the package photo.
        if let guessedName = try? await visionService.recognizeProduct(from: image),
           let product = try? await offService.searchProduct(byName: guessedName) {
            currentProduct = product
            notifyScanSucceeded()
            isLoading = false
            return
        }

        // Step 2: didn't work — read the ingredient list straight off the label via OCR.
        ocrService.recognizeText(in: image) { [weak self] recognizedText in
            guard let self else { return }
            Task { @MainActor in
                await self.resolveFromOCR(text: recognizedText)
            }
        }
    }

    private func resolveFromOCR(text: String) async {
        let firstLine = text.components(separatedBy: .newlines).first ?? text

        do {
            let product = try await offService.searchProduct(byName: firstLine)
            currentProduct = product
            notifyScanSucceeded()
        } catch {
            let detectedAllergens = ocrService.detectAllergens(inText: text)
            if detectedAllergens.isEmpty && text.isEmpty {
                errorMessage = "Couldn't recognize the product. Try scanning the barcode or photographing the ingredient list up close."
            } else {
                currentProduct = Product(
                    id: UUID().uuidString,
                    name: "Product not found in the database — allergens detected from the ingredient list",
                    brand: nil,
                    imageURL: nil,
                    ingredientsText: text.isEmpty ? nil : text,
                    allergens: detectedAllergens,
                    traceAllergens: [],
                    qualityGrade: .unknown,
                    novaGroup: nil,
                    nutriments: nil,
                    additives: [],
                    isOrganic: false,
                    healthScore: nil,
                    source: .ocrFallback
                )
                notifyScanSucceeded()
            }
        }
        isLoading = false
    }

    /// Silent haptic-only confirmation that a scan resolved to a product —
    /// deliberately no extra on-screen UI, just a tactile cue.
    private func notifyScanSucceeded() {
        successHaptic.prepare()
        successHaptic.notificationOccurred(.success)
    }

    // MARK: - Risk check for this specific user

    func riskyAllergens(for product: Product) -> [Allergen] {
        product.allergens.filter { userAllergyProfile.contains($0) }
    }

    func riskyTraceAllergens(for product: Product) -> [Allergen] {
        product.traceAllergens.filter { userAllergyProfile.contains($0) }
    }

    func riskLevel(for product: Product) -> RiskLevel {
        if !riskyAllergens(for: product).isEmpty { return .danger }
        if !riskyTraceAllergens(for: product).isEmpty { return .caution }
        return .safe
    }

    enum RiskLevel {
        case safe, caution, danger

        var color: Color {
            switch self {
            case .safe: return .green
            case .caution: return .orange
            case .danger: return .red
            }
        }

        var label: String {
            switch self {
            case .safe: return "Safe for you"
            case .caution: return "May contain traces of your allergens"
            case .danger: return "Contains your allergens!"
            }
        }
    }
}
