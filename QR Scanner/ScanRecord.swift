import Foundation
import SwiftData

@Model
final class ScanRecord {
    var rawValue: String
    var kindRaw: String
    var symbology: String?
    var createdAt: Date
    var isFavorite: Bool

    init(rawValue: String,
         kindRaw: String,
         symbology: String? = nil,
         createdAt: Date = .now,
         isFavorite: Bool = false) {
        self.rawValue = rawValue
        self.kindRaw = kindRaw
        self.symbology = symbology
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }
}
