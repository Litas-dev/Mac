import Foundation

protocol TransactionRepository {
    func loadTransactions() -> [Transaction]
    func save(transactions: [Transaction]) throws
}

final class FileTransactionRepository: TransactionRepository {
    private let url: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    init(fileURL: URL? = nil) {
        if let fileURL { self.url = fileURL }
        else {
            self.url = PersistencePaths.localBaseDirectory()
                .appendingPathComponent("transactions.json", isDirectory: false)
        }
    }
    
    func loadTransactions() -> [Transaction] {
        do {
            try ensureParentDir()
            guard fm.fileExists(atPath: url.path) else { return [] }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode([Transaction].self, from: data)
            } catch {
                preserveCorruptFile()
                return []
            }
        } catch {
            return []
        }
    }
    
    func save(transactions: [Transaction]) throws {
        try ensureParentDir()
        let data = try encoder.encode(transactions)
        try data.write(to: url, options: .atomic)
    }
    
    private func ensureParentDir() throws {
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    private func preserveCorruptFile() {
        guard fm.fileExists(atPath: url.path) else { return }
        let df = ISO8601DateFormatter()
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(df.string(from: Date()))")
            .appendingPathExtension("json")
        _ = try? fm.copyItem(at: url, to: backupURL)
    }
}
