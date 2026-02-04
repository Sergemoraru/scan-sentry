import Foundation
import SwiftData

@Model
final class DocumentRecord {
    var id: UUID
    var title: String
    var createdAt: Date
    var pageImagePaths: [String]

    init(title: String = "Scanned Document",
         createdAt: Date = .now,
         pageImagePaths: [String] = []) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.pageImagePaths = pageImagePaths
    }
}
