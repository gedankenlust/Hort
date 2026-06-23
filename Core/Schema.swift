import Foundation

enum MemoryType: String, Codable, CaseIterable {
    case text
    case url
    case image
    case screenshot
    case file
}

struct MemoryObject: Identifiable, Codable {
    let id: UUID
    var type: MemoryType
    var createdAt: Date
    var updatedAt: Date
    
    var sourceApp: String?
    var sourceWindow: String?
    
    var content: String? // Plain text or file path
    var preview: String? // Preview text or image path
    var thumbnailPath: String?
    
    var attachments: [String] = []
    var tags: [String] = []
    var board: String?
    var folder: String?
    
    var isFavorite: Bool = false
    var isArchived: Bool = false
    
    var securityLevel: Int = 0
    var version: Int = 1
    
    var metadata: [String: String] = [:]
    var relatedObjectIDs: [UUID] = []
    
    init(id: UUID = UUID(), type: MemoryType, content: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
