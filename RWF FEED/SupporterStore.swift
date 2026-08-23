//
//  SupporterStore.swift
//  RWF FEED
//
//  A single non-consumable IAP ("Supporter") that removes ads and unlocks alternate app
//  icons. StoreKit 2 only — no receipt validation server needed since entitlement state is
//  read straight from Transaction.currentEntitlements, which StoreKit itself keeps in sync
//  with Apple's servers (including restores across devices signed into the same Apple ID).
//

import Combine
import StoreKit

@MainActor
final class SupporterStore: ObservableObject {
    static let shared = SupporterStore()

    static let productID = "RIO.RWF-FEED.supporter"

    @Published private(set) var isSupporter = false
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    /// Distinguishes "still fetching" from "fetched, found nothing" — without this, a
    /// product that never loads (IAP not yet live in App Store Connect, no network) leaves
    /// the Settings UI showing a progress spinner forever with no explanation.
    @Published private(set) var hasAttemptedProductLoad = false
    @Published var errorMessage: String?

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        transactionListenerTask = listenForTransactionUpdates()
        Task {
            await loadProduct()
            await updateEntitlementStatus()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            NSLog("SupporterStore: failed to load product: %@", String(describing: error))
        }
        hasAttemptedProductLoad = true
    }

    func purchase() async {
        guard let product else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlementStatus()
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                // Awaiting approval (e.g. Ask to Buy) — listenForTransactionUpdates picks
                // this up once it resolves, nothing to do here.
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
            NSLog("SupporterStore: purchase failed: %@", String(describing: error))
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateEntitlementStatus()
        } catch {
            errorMessage = "Restore failed. Please try again."
            NSLog("SupporterStore: restore failed: %@", String(describing: error))
        }
    }

    private func updateEntitlementStatus() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                purchased = true
            }
        }
        isSupporter = purchased
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self, let transaction = try? await self.checkVerified(result) else { continue }
                await self.updateEntitlementStatus()
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
