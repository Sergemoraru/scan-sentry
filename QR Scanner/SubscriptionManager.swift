import Foundation
import StoreKit
import SwiftUI

@Observable
final class SubscriptionManager {
    // MARK: - Product IDs
    static let proMonthlyProductID = "com.safeqr.pro.monthly"
    
    // MARK: - Usage Limits
    static let freeScanLimit = 3
    static let freeDocumentLimit = 1
    
    // MARK: - Persisted State
    @ObservationIgnored
    @AppStorage("scanCount") private var storedScanCount: Int = 0
    
    @ObservationIgnored
    @AppStorage("documentCount") private var storedDocumentCount: Int = 0
    
    // MARK: - Published State
    var isPro: Bool = false
    var products: [Product] = []
    var purchaseInProgress: Bool = false
    var errorMessage: String?
    
    var scanCount: Int {
        get { storedScanCount }
        set { storedScanCount = newValue }
    }
    
    var documentCount: Int {
        get { storedDocumentCount }
        set { storedDocumentCount = newValue }
    }
    
    var canScan: Bool {
        isPro || scanCount < Self.freeScanLimit
    }
    
    var canScanDocument: Bool {
        isPro || documentCount < Self.freeDocumentLimit
    }
    
    var remainingScans: Int {
        max(0, Self.freeScanLimit - scanCount)
    }
    
    var remainingDocuments: Int {
        max(0, Self.freeDocumentLimit - documentCount)
    }
    
    // MARK: - Transaction Listener
    private var transactionListener: Task<Void, Never>?
    
    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Load Products
    @MainActor
    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.proMonthlyProductID])
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Purchase
    @MainActor
    func purchase() async {
        guard let product = products.first else {
            errorMessage = "Product not available"
            return
        }
        
        purchaseInProgress = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateSubscriptionStatus()
                
            case .userCancelled:
                break
                
            case .pending:
                errorMessage = "Purchase is pending approval"
                
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
        
        purchaseInProgress = false
    }
    
    // MARK: - Restore Purchases
    @MainActor
    func restorePurchases() async {
        purchaseInProgress = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
        
        purchaseInProgress = false
    }
    
    // MARK: - Update Subscription Status
    @MainActor
    func updateSubscriptionStatus() async {
        var hasActiveSubscription = false
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proMonthlyProductID {
                    hasActiveSubscription = true
                    break
                }
            }
        }
        
        isPro = hasActiveSubscription
    }
    
    // MARK: - Transaction Listener
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.updateSubscriptionStatus()
                }
            }
        }
    }
    
    // MARK: - Verification Helper
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case verificationFailed
}
