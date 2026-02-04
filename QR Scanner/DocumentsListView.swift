import SwiftUI
import SwiftData

struct DocumentsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentRecord.createdAt, order: .reverse) private var documents: [DocumentRecord]
    
    @State private var showingScanner = false
    @State private var selectedDocument: DocumentRecord?
    
    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("Tap the + button to scan your first document.")
                    }
                } else {
                    List {
                        ForEach(documents) { doc in
                            Button {
                                selectedDocument = doc
                            } label: {
                                DocumentRow(document: doc)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteDocuments)
                    }
                }
            }
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    saveDocument(images: images)
                }
            }
            .sheet(item: $selectedDocument) { doc in
                DocumentDetailView(document: doc)
            }
        }
    }
    
    private func saveDocument(images: [UIImage]) {
        guard !images.isEmpty else { return }
        
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docId = UUID()
        let docFolder = documentsDir.appendingPathComponent("ScannedDocs/\(docId.uuidString)", isDirectory: true)
        
        try? fileManager.createDirectory(at: docFolder, withIntermediateDirectories: true)
        
        var pagePaths: [String] = []
        for (index, image) in images.enumerated() {
            let fileName = "page_\(index).jpg"
            let fileURL = docFolder.appendingPathComponent(fileName)
            if let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: fileURL)
                pagePaths.append(fileURL.path)
            }
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let title = "Scan \(formatter.string(from: Date()))"
        
        let record = DocumentRecord(title: title, pageImagePaths: pagePaths)
        modelContext.insert(record)
    }
    
    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            let doc = documents[index]
            // Delete files
            let fileManager = FileManager.default
            for path in doc.pageImagePaths {
                try? fileManager.removeItem(atPath: path)
            }
            // Delete parent folder if empty
            if let firstPath = doc.pageImagePaths.first {
                let folderURL = URL(fileURLWithPath: firstPath).deletingLastPathComponent()
                try? fileManager.removeItem(at: folderURL)
            }
            modelContext.delete(doc)
        }
    }
}

struct DocumentRow: View {
    let document: DocumentRecord
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let firstPath = document.pageImagePaths.first,
               let uiImage = UIImage(contentsOfFile: firstPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 65)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 50, height: 65)
                    .overlay {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(document.pageImagePaths.count) page\(document.pageImagePaths.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(document.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
