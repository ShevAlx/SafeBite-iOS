import Foundation
import StoreKit

/// Owns the app's subscription state via StoreKit 2. The whole app is gated
/// behind an active subscription (see ContentView) — the free month is just
/// the introductory offer on these products, configured in App Store Connect,
/// not a separate code path.
@MainActor
final class SubscriptionManager: ObservableObject {

    static let monthlyID = "com.vibecoding.ProductScanner.premium.monthly"
    static let annualID = "com.vibecoding.ProductScanner.premium.annual"

    @Published private(set) var products: [StoreKit.Product] = []
    @Published private(set) var isSubscribed = false
    @Published var errorMessage: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await StoreKit.Product.products(for: [Self.monthlyID, Self.annualID])
        } catch {
            errorMessage = "Couldn't load subscription options: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: StoreKit.Product) async {
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.monthlyID || transaction.productID == Self.annualID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
