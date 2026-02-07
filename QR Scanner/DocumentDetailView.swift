import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager
    let document: DocumentRecord
    
    @State private var currentPage = 0
    @State private var showingShareSheet = false
    @State private var showingPaywall = false
    @State private var pdfURL: URL?
    
    private var images: [UIImage] {
        document.pageImagePaths.compactMap { UIImage(contentsOfFile: $0) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if images.isEmpty {
                    ContentUnavailableView("No Pages", systemImage: "doc.questionmark")
                } else {
                    TabView(selection: $currentPage) {
                        ForEach(images.indices, id: \.self) { index in
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    
                    // Page indicator
                    if images.count > 1 {
                        Text("Page \(currentPage + 1) of \(images.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard subscriptionManager.canExportPDF else {
                            showingPaywall = true
                            return
                        }

                        let didGenerate = generateAndSharePDF()
                        if didGenerate {
                            subscriptionManager.consumeFreeUse(for: .pdfExport)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }
    
    private func generateAndSharePDF() -> Bool {
        guard !images.isEmpty else { return false }
        
        let pdfDocument = PDFDocument()
        
        for (index, image) in images.enumerated() {
            if let page = PDFPage(image: image) {
                pdfDocument.insert(page, at: index)
            }
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = document.title.replacingOccurrences(of: " ", with: "_") + ".pdf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        guard pdfDocument.write(to: fileURL) else { return false }
        pdfURL = fileURL
        showingShareSheet = true
        return true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
