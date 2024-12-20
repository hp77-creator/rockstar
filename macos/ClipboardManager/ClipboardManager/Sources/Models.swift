import Foundation

struct ClipboardItem: Codable, Identifiable {
    let id: Int
    let content: String
    let type: String
    let createdAt: Date
    let metadata: ClipMetadata
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case content = "Content"
        case type = "Type"
        case createdAt = "CreatedAt"
        case metadata = "Metadata"
    }
}

struct ClipMetadata: Codable {
    let sourceApp: String?
    
    enum CodingKeys: String, CodingKey {
        case sourceApp = "SourceApp"
    }
}
