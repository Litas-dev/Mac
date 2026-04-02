import Foundation

enum PersistencePaths {
    static func isICloudAvailable() -> Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }
    
    static func localBaseDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("PersonalFinances", isDirectory: true)
    }
    
    static func iCloudBaseDirectory() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("PersonalFinances", isDirectory: true)
    }
    
    static func baseDirectory(preferICloud: Bool) -> URL {
        if preferICloud, let cloud = iCloudBaseDirectory() {
            return cloud
        }
        return localBaseDirectory()
    }
    
    static func fileURL(_ name: String, preferICloud: Bool) -> URL {
        baseDirectory(preferICloud: preferICloud).appendingPathComponent(name, isDirectory: false)
    }
    
    static let dataFiles: [String] = [
        "bills.json",
        "incomes.json",
        "accounts.json",
        "transactions.json",
        "goals.json",
        "debts.json"
    ]
}

enum PersistenceMigration {
    static func migrateAll(from sourceBase: URL, to targetBase: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: targetBase.path) {
            try fm.createDirectory(at: targetBase, withIntermediateDirectories: true)
        }
        
        for name in PersistencePaths.dataFiles {
            let src = sourceBase.appendingPathComponent(name, isDirectory: false)
            let dst = targetBase.appendingPathComponent(name, isDirectory: false)
            if !fm.fileExists(atPath: src.path) { continue }
            
            if fm.fileExists(atPath: dst.path) {
                let backup = dst.deletingPathExtension()
                    .appendingPathExtension("backup-\(timestamp())")
                    .appendingPathExtension("json")
                _ = try? fm.copyItem(at: dst, to: backup)
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
    }
    
    static func deleteICloudData() throws {
        let fm = FileManager.default
        guard let base = PersistencePaths.iCloudBaseDirectory() else { return }
        guard fm.fileExists(atPath: base.path) else { return }
        try fm.removeItem(at: base)
    }
    
    private static func timestamp() -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}

