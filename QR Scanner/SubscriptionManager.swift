import Foundation
import StoreKit
import SwiftUI

enum PremiumFeature: String, CaseIterable {
    case scan
    case documentScan
    case qrExport
    case pdfExport
}

@Observable
final class SubscriptionManager {
    // MARK: - Product IDs
    static let proMonthlyProductID = "com.safeqr.pro.monthly"
    
    // MARK: - Usage Limits
    static let freeUsageLimitPerFeature = 1
    
    // MARK: - Persisted State
    @ObservationIgnored
    @AppStorage("scanCount") private var storedScanCount: Int = 0
    
    @ObservationIgnored
    @AppStorage("documentCount") private var storedDocumentCount: Int = 0

    @ObservationIgnored
    @AppStorage("qrExportCount") private var storedQRCodeExportCount: Int = 0

    @ObservationIgnored
    @AppStorage("pdfExportCount") private var storedPDFExportCount: Int = 0

#if DEBUG
    @ObservationIgnored
    @AppStorage("debugForcePro") private var storedDebugForcePro: Bool = false
#endif
    
    // MARK: - Published State
    private var hasActiveSubscription: Bool = false
#if DEBUG
    var debugForcePro: Bool = false
#endif
    var products: [Product] = []
    var purchaseInProgress: Bool = false
    var errorMessage: String?

    var isPro: Bool {
#if DEBUG
        hasActiveSubscription || debugForcePro
#else
        hasActiveSubscription
#endif
    }
    
    var canScan: Bool {
        canUse(.scan)
    }
    
    var canScanDocument: Bool {
        canUse(.documentScan)
    }

    var canExportQRCode: Bool {
        canUse(.qrExport)
    }

    var canExportPDF: Bool {
        canUse(.pdfExport)
    }
    
    var remainingScans: Int {
        remainingFreeUses(for: .scan)
    }
    
    var remainingDocuments: Int {
        remainingFreeUses(for: .documentScan)
    }

    var remainingQRCodeExports: Int {
        remainingFreeUses(for: .qrExport)
    }

    var remainingPDFExports: Int {
        remainingFreeUses(for: .pdfExport)
    }

    func canUse(_ feature: PremiumFeature) -> Bool {
        isPro || usageCount(for: feature) < Self.freeUsageLimitPerFeature
    }

    func consumeFreeUse(for feature: PremiumFeature) {
        guard !isPro else { return }
        let current = usageCount(for: feature)
        let updated = min(Self.freeUsageLimitPerFeature, current + 1)
        setUsageCount(updated, for: feature)
    }

    private func remainingFreeUses(for feature: PremiumFeature) -> Int {
        max(0, Self.freeUsageLimitPerFeature - usageCount(for: feature))
    }

    private func usageCount(for feature: PremiumFeature) -> Int {
        switch feature {
        case .scan:
            return storedScanCount
        case .documentScan:
            return storedDocumentCount
        case .qrExport:
            return storedQRCodeExportCount
        case .pdfExport:
            return storedPDFExportCount
        }
    }

    private func setUsageCount(_ value: Int, for feature: PremiumFeature) {
        switch feature {
        case .scan:
            storedScanCount = value
        case .documentScan:
            storedDocumentCount = value
        case .qrExport:
            storedQRCodeExportCount = value
        case .pdfExport:
            storedPDFExportCount = value
        }
    }
    
    // MARK: - Transaction Listener
    private var transactionListener: Task<Void, Never>?
    
    init() {
#if DEBUG
        debugForcePro = storedDebugForcePro
#endif
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
        var hasSubscription = false
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proMonthlyProductID {
                    hasSubscription = true
                    break
                }
            }
        }
        
        hasActiveSubscription = hasSubscription
    }

#if DEBUG
    @MainActor
    func setDebugForcePro(_ enabled: Bool) {
        debugForcePro = enabled
        storedDebugForcePro = enabled
    }
#endif
    
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
