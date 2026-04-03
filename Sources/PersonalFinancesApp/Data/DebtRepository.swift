import Foundation

protocol DebtRepository {
    func loadDebts() -> [Debt]
    func save(debts: [Debt]) throws
}

final class FileDebtRepository: DebtRepository {
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
                .appendingPathComponent("debts.json", isDirectory: false)
        }
    }
    
    func loadDebts() -> [Debt] {
        do {
            try ensureParentDir()
            guard fm.fileExists(atPath: url.path) else { return [] }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode([Debt].self, from: data)
            } catch {
                preserveCorruptFile()
                return []
            }
        } catch {
            return []
        }
    }
    
    func save(debts: [Debt]) throws {
        try ensureParentDir()
        let data = try encoder.encode(debts)
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
