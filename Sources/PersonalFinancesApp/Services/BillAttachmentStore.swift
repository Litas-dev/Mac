import Foundation

final class BillAttachmentStore {
    static let shared = BillAttachmentStore()
    
    private let fm = FileManager.default
    
    private init() {}
    
    func attachmentsRootURL() throws -> URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport
            .appendingPathComponent("PersonalFinances", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }
    
    func resolve(_ attachment: BillAttachment) throws -> URL {
        let root = try attachmentsRootURL()
        return root.appendingPathComponent(attachment.storedRelativePath, isDirectory: false)
    }
    
    func save(sourceURL: URL, billId: UUID, displayName: String? = nil) throws -> BillAttachment {
        let root = try attachmentsRootURL()
        let billDir = root.appendingPathComponent(billId.uuidString, isDirectory: true)
        if !fm.fileExists(atPath: billDir.path) {
            try fm.createDirectory(at: billDir, withIntermediateDirectories: true)
        }
        
        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let storedFileName = "\(id.uuidString).\(ext)"
        let dest = billDir.appendingPathComponent(storedFileName, isDirectory: false)
        
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        
        let relative = billId.uuidString + "/" + storedFileName
        return BillAttachment(
            id: id,
            displayName: (displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? displayName!.trimmingCharacters(in: .whitespacesAndNewlines)
                : (sourceURL.lastPathComponent.isEmpty ? storedFileName : sourceURL.lastPathComponent),
            storedRelativePath: relative,
            createdAt: Date()
        )
    }
    
    func delete(_ attachment: BillAttachment) {
        do {
            let url = try resolve(attachment)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        } catch {
            return
        }
    }
    
    func deleteAllAttachments() {
        do {
            let root = try attachmentsRootURL()
            if fm.fileExists(atPath: root.path) {
                try fm.removeItem(at: root)
            }
        } catch {
            return
        }
    }
}
