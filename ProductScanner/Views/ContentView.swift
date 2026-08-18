import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = ProductScanViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingAllergyProfile = false
    @State private var showingProductDetail = false
    @State private var showingGate = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                BarcodeScannerView(
                    onBarcodeDetected: { code in viewModel.handleBarcode(code) },
                    onPhotoCaptured: { image in viewModel.handlePhoto(image) }
                )
                .ignoresSafeArea()

                scanFrameOverlay

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomContent
                }
            }
            .navigationTitle("SafeBite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAllergyProfile) {
                AllergyProfileView(selected: $viewModel.userAllergyProfile)
            }
            .fullScreenCover(isPresented: $showingGate) {
                if !viewModel.hasCompletedOnboarding {
                    OnboardingView(selected: $viewModel.userAllergyProfile) {
                        viewModel.hasCompletedOnboarding = true
                    }
                } else {
                    PaywallView(subscriptionManager: subscriptionManager)
                }
            }
            .onChange(of: viewModel.hasCompletedOnboarding) { _ in updateGate() }
            .onChange(of: subscriptionManager.isSubscribed) { _ in updateGate() }
            .onAppear { updateGate() }
            .sheet(isPresented: $showingProductDetail) {
                if let product = viewModel.currentProduct {
                    ProductDetailView(
                        product: product,
                        riskLevel: viewModel.riskLevel(for: product),
                        riskyAllergens: viewModel.riskyAllergens(for: product),
                        riskyTraceAllergens: viewModel.riskyTraceAllergens(for: product)
                    )
                }
            }
            .onChange(of: photoPickerItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.handlePhoto(image)
                    }
                }
            }
        }
    }

    private func updateGate() {
        showingGate = !viewModel.hasCompletedOnboarding || !subscriptionManager.isSubscribed
    }

    // MARK: - Scan frame: dims everything outside a centered square viewfinder,
    // so the camera preview isn't full-screen and the top/bottom chrome stays legible.

    private var scanFrameOverlay: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.7

            ZStack {
                Color.black.opacity(0.55)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .frame(width: side, height: side)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: side, height: side)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Top bar: floating glass title + allergy profile shortcut

    private var topBar: some View {
        HStack {
            Spacer()
            Text("SafeBite")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassBackground(in: Capsule())
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button {
                showingAllergyProfile = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassBackground(in: Circle())
            }
            .accessibilityLabel("My allergens")
            .padding(.trailing, 16)
        }
        .padding(.top, 8)
    }

    // MARK: - Bottom: result card + single glass action bar

    private var bottomContent: some View {
        VStack(spacing: 14) {
            if viewModel.isLoading {
                ProgressView("Analyzing product…")
                    .padding()
                    .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding()
                    .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let product = viewModel.currentProduct {
                Button {
                    showingProductDetail = true
                } label: {
                    ProductResultCard(
                        product: product,
                        riskLevel: viewModel.riskLevel(for: product),
                        riskyAllergens: viewModel.riskyAllergens(for: product)
                    )
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .glassBackground(in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }
}

// MARK: - Result card

struct ProductResultCard: View {
    let product: Product
    let riskLevel: ProductScanViewModel.RiskLevel
    let riskyAllergens: [Allergen]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let brand = product.brand {
                        Text(brand).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                scoreBadge
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(riskLevel.label)
                .font(.subheadline.bold())
                .foregroundStyle(riskLevel.color)

            if !product.allergens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(product.allergens) { allergen in
                            let isRisky = riskyAllergens.contains(allergen)
                            Text("\(allergen.icon) \(allergen.displayName)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isRisky ? Color.red.opacity(0.2) : Color.gray.opacity(0.15))
                                .foregroundStyle(isRisky ? .red : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Text("Tap for full details")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Glanceable rating: the 0–100 health score when we could compute one,
    /// otherwise the raw Nutri-Score letter as a fallback.
    @ViewBuilder
    private var scoreBadge: some View {
        if let score = product.healthScore {
            VStack(spacing: 0) {
                Text("\(score.total)").font(.headline.bold().monospacedDigit())
                Text(score.category.label).font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color(score.category.colorName))
            .clipShape(Circle())
            .accessibilityLabel("Health score \(score.total) out of 100, \(score.category.label)")
        } else {
            Text(product.qualityGrade.rawValue)
                .font(.caption.bold())
                .padding(6)
                .background(Color(product.qualityGrade.colorName))
                .clipShape(Circle())
                .accessibilityLabel("Nutri-Score \(product.qualityGrade.rawValue)")
        }
    }
}

// MARK: - User allergy profile

struct AllergyProfileView: View {
    @Binding var selected: Set<Allergen>
    @Environment(\.dismiss) private var dismiss
    @State private var showingManageSubscriptions = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Allergen.allCases) { allergen in
                        Toggle(isOn: Binding(
                            get: { selected.contains(allergen) },
                            set: { isOn in
                                if isOn { selected.insert(allergen) } else { selected.remove(allergen) }
                            }
                        )) {
                            Label {
                                Text(allergen.displayName)
                            } icon: {
                                Text(allergen.icon)
                            }
                        }
                        .tint(.red)
                    }
                } header: {
                    Text("Allergens")
                } footer: {
                    Text("We'll flag any of these found in a scanned product, including \"may contain traces\" cross-contact warnings.")
                }

                Section {
                    Button("Manage Subscription") {
                        showingManageSubscriptions = true
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("My Allergens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        }
    }
}

#Preview {
    ContentView()
}
