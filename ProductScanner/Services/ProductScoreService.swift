import Foundation

/// Computes the Yuka-style 0–100 health score from the data we get out of
/// Open Food Facts. Pure and deterministic — same inputs always yield the same
/// score, which is what makes the result trustworthy and testable.
///
/// Weighting mirrors Yuka's published methodology for food:
///   • 60% nutritional quality  (derived from the Nutri-Score)
///   • 30% additives            (driven by the most hazardous additive present)
///   • 10% organic bonus
enum ProductScoreService {

    /// - Parameters:
    ///   - nutriScore: numeric Nutri-Score points (OFF `nutriscore_score`),
    ///     roughly −15 (best) … 40 (worst) for foods. Preferred input.
    ///   - grade: letter grade, used only when the numeric score is missing.
    ///   - additives: additives detected on the product.
    ///   - isOrganic: whether the product carries an organic certification.
    /// - Returns: a `HealthScore`, or `nil` when there isn't enough data to
    ///   rate the product (no nutritional signal at all).
    static func score(nutriScore: Double?,
                      grade: QualityGrade,
                      additives: [Additive],
                      isOrganic: Bool) -> HealthScore? {

        guard let nutrition = nutritionPoints(nutriScore: nutriScore, grade: grade) else {
            return nil
        }

        let additivePoints = additivePoints(additives)
        let organic = isOrganic ? 10 : 0

        var total = max(0, min(100, nutrition + additivePoints + organic))

        // Hard cap (Yuka-style): a single hazardous additive — nitrites, azo
        // dyes, BHA/BHT… — drags the whole product into "Bad", regardless of how
        // good its nutrition is. A great nutritional profile shouldn't rescue a
        // product that contains an additive best avoided.
        if additives.contains(where: { $0.risk == .high }) {
            total = min(total, hazardousAdditiveCap)
        }

        return HealthScore(total: total,
                           nutrition: nutrition,
                           additives: additivePoints,
                           organicBonus: organic)
    }

    /// Ceiling applied when a hazardous additive is present — top of the "Bad"
    /// band, so the product always reads as Bad.
    private static let hazardousAdditiveCap = 24

    // MARK: - Nutrition (0–60)

    /// Maps the Nutri-Score onto a 0–60 band. Uses the fine-grained numeric
    /// score when available, and falls back to a per-grade midpoint otherwise.
    private static func nutritionPoints(nutriScore: Double?, grade: QualityGrade) -> Int? {
        if let s = nutriScore {
            // Food scale: −15 (best) … 40 (worst). Clamp, invert, scale to 60.
            let clamped = max(-15.0, min(40.0, s))
            let fraction = (40.0 - clamped) / 55.0      // 0…1, higher = healthier
            return Int((fraction * 60.0).rounded())
        }

        // No numeric score — approximate from the letter grade.
        switch grade {
        case .a: return 57
        case .b: return 46
        case .c: return 33
        case .d: return 19
        case .e: return 6
        case .unknown: return nil
        }
    }

    // MARK: - Additives (0–30)

    /// Starts from a clean 30 and lets the worst additive drag the band down,
    /// with a smaller extra penalty when several risky additives stack up —
    /// so "one hazardous additive" behaves like Yuka's hard cap.
    private static func additivePoints(_ additives: [Additive]) -> Int {
        guard let worst = additives.map(\.risk).max() else { return 30 }

        let base: Int
        switch worst {
        case .riskFree: base = 30
        case .limited:  base = 25
        case .moderate: base = 15
        case .high:     base = 0
        }

        // Each additional non-trivial additive shaves a little more off.
        let riskyCount = additives.filter { $0.risk >= .moderate }.count
        let stacking = max(0, riskyCount - 1) * 3

        return max(0, base - stacking)
    }
}
