import SwiftUI
import StoreKit

/// Blocking screen shown whenever there's no active subscription — scanning
/// is fully gated behind it. The free month comes from the introductory
/// offer configured on these products in App Store Connect; tapping a plan
/// here starts that trial, it isn't a separate free path in this screen.
struct PaywallView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("SafeBite Premium")
                            .font(.largeTitle.bold())
                        Text("1 month free, then continue for less than a coffee. Cancel anytime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 24)

                    if subscriptionManager.products.isEmpty {
                        ProgressView()
                            .padding()
                    } else {
                        VStack(spacing: 12) {
                            ForEach(sortedProducts) { product in
                                planButton(for: product)
                            }
                        }
                        .padding(.horizontal, 24)
                        .disabled(isPurchasing)
                    }

                    if let error = subscriptionManager.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button("Restore Purchases") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.footnote)

                    Text("After the free month, your plan auto-renews at the price shown above until you cancel. Manage or cancel anytime in Settings > Apple ID > Subscriptions.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private var sortedProducts: [StoreKit.Product] {
        subscriptionManager.products.sorted { $0.price < $1.price }
    }

    private func planButton(for product: StoreKit.Product) -> some View {
        Button {
            isPurchasing = true
            Task {
                await subscriptionManager.purchase(product)
                isPurchasing = false
            }
        } label: {
            VStack(spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                Text(priceLabel(for: product))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func priceLabel(for product: StoreKit.Product) -> String {
        let period = product.id == SubscriptionManager.annualID ? "year" : "month"
        return "\(product.displayPrice) / \(period)"
    }
}

#Preview {
    PaywallView(subscriptionManager: SubscriptionManager())
}
