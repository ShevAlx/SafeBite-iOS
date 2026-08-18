import SwiftUI

/// Full product detail sheet, opened by tapping the result card — surfaces
/// everything the compact card leaves out: full allergen picture (including
/// "may contain traces" cross-contact warnings), nutrition facts, the full
/// ingredient list, and what the NOVA processing group means.
struct ProductDetailView: View {
    let product: Product
    let riskLevel: ProductScanViewModel.RiskLevel
    let riskyAllergens: [Allergen]
    let riskyTraceAllergens: [Allergen]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if let score = product.healthScore {
                    scoreSection(score)
                }

                if !product.allergens.isEmpty || !product.traceAllergens.isEmpty {
                    allergenSection
                }

                if !product.additives.isEmpty {
                    additivesSection
                }

                if let nutriments = product.nutriments, !nutriments.isEmpty {
                    nutritionSection(nutriments)
                }

                if let novaGroup = product.novaGroup {
                    novaSection(novaGroup)
                }

                if let ingredients = product.ingredientsText, !ingredients.isEmpty {
                    Section("Ingredients") {
                        Text(ingredients).font(.footnote)
                    }
                }

                Section {
                    Text("Data from Open Food Facts, a free, open database maintained by volunteers, cross-checked against USDA FoodData Central where available.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("This app helps flag likely allergens but can't guarantee this product is safe for you — entries can be outdated or incomplete. Always check the physical packaging yourself.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Product Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: product.imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.15))
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.title3.bold())
                        if let brand = product.brand {
                            Text(brand).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text(product.qualityGrade.rawValue)
                                .font(.caption.bold())
                                .padding(6)
                                .background(Color(product.qualityGrade.colorName))
                                .clipShape(Circle())
                            Text(product.qualityGrade.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Label(riskLevel.label, systemImage: riskIcon)
                    .font(.subheadline.bold())
                    .foregroundStyle(riskLevel.color)
            }
            .padding(.vertical, 4)
        }
    }

    private func scoreSection(_ score: HealthScore) -> some View {
        Section("Health score") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    // Big number, colored by category.
                    ZStack {
                        Circle()
                            .fill(Color(score.category.colorName).opacity(0.18))
                        VStack(spacing: 0) {
                            Text("\(score.total)")
                                .font(.title.bold())
                                .foregroundStyle(Color(score.category.colorName))
                            Text("/100").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(score.category.label)
                            .font(.headline)
                            .foregroundStyle(Color(score.category.colorName))
                        Text("Based on nutrition, additives and organic labelling.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Breakdown of the three weighted components.
                VStack(spacing: 6) {
                    scoreBar("Nutrition", value: score.nutrition, outOf: 60)
                    scoreBar("Additives", value: score.additives, outOf: 30)
                    scoreBar("Organic", value: score.organicBonus, outOf: 10)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Health score \(score.total) out of 100, \(score.category.label)")
        }
    }

    private func scoreBar(_ title: String, value: Int, outOf: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * CGFloat(value) / CGFloat(outOf))
                }
            }
            .frame(height: 6)
            Text("\(value)/\(outOf)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var additivesSection: some View {
        Section {
            ForEach(product.additives) { additive in
                HStack {
                    Circle()
                        .fill(Color(additive.risk.colorName))
                        .frame(width: 10, height: 10)
                    Text(additive.displayName).font(.footnote)
                    Spacer()
                    Text(additive.risk.label)
                        .font(.caption2)
                        .foregroundStyle(Color(additive.risk.colorName))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(additive.displayName), \(additive.risk.label)")
            }
        } header: {
            Text("Additives (\(product.additives.count))")
        } footer: {
            Text("Risk ratings are a general guide based on EFSA/ANSES/IARC positions, not medical advice.")
        }
    }

    private var allergenSection: some View {
        Section {
            if !product.allergens.isEmpty {
                allergenRow(title: "Contains", allergens: product.allergens, risky: riskyAllergens, tint: .red)
            }
            if !product.traceAllergens.isEmpty {
                allergenRow(title: "May contain traces of", allergens: product.traceAllergens, risky: riskyTraceAllergens, tint: .orange)
            }
        } header: {
            Text("Allergens")
        } footer: {
            if !product.traceAllergens.isEmpty {
                Text("\"May contain traces\" means the manufacturer warns about possible cross-contact on shared equipment — not a confirmed ingredient, but still worth caution.")
            }
        }
    }

    private func nutritionSection(_ nutriments: Nutriments) -> some View {
        Section("Nutrition — per 100 g") {
            nutrientRow("Calories", nutriments.energyKcal, unit: "kcal")
            nutrientRow("Fat", nutriments.fat, unit: "g")
            nutrientRow("of which saturated", nutriments.saturatedFat, unit: "g")
            nutrientRow("Carbohydrates", nutriments.carbohydrates, unit: "g")
            nutrientRow("of which sugars", nutriments.sugars, unit: "g")
            nutrientRow("Fiber", nutriments.fiber, unit: "g")
            nutrientRow("Protein", nutriments.proteins, unit: "g")
            nutrientRow("Salt", nutriments.salt, unit: "g")
        }
    }

    private func novaSection(_ novaGroup: Int) -> some View {
        Section("Processing (NOVA)") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Group \(novaGroup)").font(.subheadline.bold())
                Text(Self.novaGroupDescription(novaGroup))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func novaGroupDescription(_ group: Int) -> String {
        switch group {
        case 1: return "Unprocessed or minimally processed food"
        case 2: return "Processed culinary ingredient"
        case 3: return "Processed food"
        case 4: return "Ultra-processed food"
        default: return "No data"
        }
    }

    // MARK: - Helpers

    private var riskIcon: String {
        switch riskLevel {
        case .safe: return "checkmark.seal.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    @ViewBuilder
    private func allergenRow(title: String, allergens: [Allergen], risky: [Allergen], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(allergens) { allergen in
                        let isRisky = risky.contains(allergen)
                        Text("\(allergen.icon) \(allergen.displayName)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isRisky ? tint.opacity(0.2) : Color.gray.opacity(0.15))
                            .foregroundStyle(isRisky ? tint : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nutrientRow(_ title: String, _ value: Double?, unit: String) -> some View {
        if let value {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ProductDetailView(
        product: Product(
            id: "0000000000000",
            name: "Sample Product",
            brand: "Sample Brand",
            imageURL: nil,
            ingredientsText: "Wheat flour, sugar, milk powder, salt.",
            allergens: [.gluten, .milk],
            traceAllergens: [.nuts],
            qualityGrade: .b,
            novaGroup: 3,
            nutriments: Nutriments(energyKcal: 450, fat: 18, saturatedFat: 9, carbohydrates: 60, sugars: 22, fiber: 2, proteins: 6, salt: 1.1),
            additives: [
                Additive(code: "E330", risk: .riskFree, name: "Citric acid"),
                Additive(code: "E322", risk: .riskFree, name: "Lecithins"),
                Additive(code: "E621", risk: .moderate, name: "Monosodium glutamate")
            ],
            isOrganic: false,
            healthScore: HealthScore(total: 58, nutrition: 46, additives: 12, organicBonus: 0),
            source: .barcode
        ),
        riskLevel: .caution,
        riskyAllergens: [],
        riskyTraceAllergens: [.nuts]
    )
}
