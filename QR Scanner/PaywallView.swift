import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.linearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        
                        Text("Upgrade to Pro")
                            .font(.largeTitle.bold())
                        
                        Text("Try every premium feature once, then unlock unlimited access")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Benefits
                    VStack(alignment: .leading, spacing: 16) {
                        BenefitRow(icon: "qrcode.viewfinder", title: "Unlimited QR Scans", subtitle: "One free scan included, then unlimited with Pro")
                        BenefitRow(icon: "doc.text.viewfinder", title: "Unlimited Document Scans", subtitle: "One free document scan included")
                        BenefitRow(icon: "square.and.arrow.up", title: "Unlimited QR Exports", subtitle: "One free QR export included")
                        BenefitRow(icon: "doc.richtext", title: "Unlimited PDF Exports", subtitle: "One free PDF export included")
                    }
                    .padding(.horizontal)

                    if !subscriptionManager.isPro {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Free tries remaining")
                                .font(.subheadline.weight(.semibold))
                            Text("QR scan: \(subscriptionManager.remainingScans)")
                            Text("Document scan: \(subscriptionManager.remainingDocuments)")
                            Text("QR export: \(subscriptionManager.remainingQRCodeExports)")
                            Text("PDF export: \(subscriptionManager.remainingPDFExports)")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Pricing
                    if let product = subscriptionManager.products.first {
                        VStack(spacing: 8) {
                            Text(product.displayPrice)
                                .font(.system(size: 44, weight: .bold))
                            
                            Text("per month")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                            Button("Try Again") {
                                Task { await subscriptionManager.loadProducts() }
                            }
                            .font(.subheadline)
                        }
                        .padding()
                    }
                    
                    // Error message
                    if let error = subscriptionManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await subscriptionManager.purchase()
                                if subscriptionManager.isPro {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                if subscriptionManager.purchaseInProgress {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Subscribe Now")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(subscriptionManager.purchaseInProgress || subscriptionManager.products.isEmpty)
                        
                        Button("Restore Purchases") {
                            Task {
                                await subscriptionManager.restorePurchases()
                                if subscriptionManager.isPro {
                                    dismiss()
                                }
                            }
                        }
                        .font(.subheadline)
                        .disabled(subscriptionManager.purchaseInProgress)
                    }
                    .padding(.horizontal)
                    
                    // Subscription disclosure (helps App Review)
                    VStack(spacing: 6) {
                        Text("Auto‑renewable subscription. Cancel anytime in Settings.")
                        if let product = subscriptionManager.products.first {
                            Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period at the rate of \(product.displayPrice) per month.")
                        } else {
                            Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                    // Legal links
                    HStack(spacing: 16) {
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Link("Privacy Policy", destination: URL(string: "https://raw.githubusercontent.com/Sergemoraru/scan-sentry/main/privacy-policy.md")!)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Link("Support", destination: URL(string: "https://raw.githubusercontent.com/Sergemoraru/scan-sentry/main/support.md")!)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionManager())
}
