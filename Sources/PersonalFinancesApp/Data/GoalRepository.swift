import Foundation

protocol GoalRepository {
    func loadGoals() -> [Goal]
    func save(goals: [Goal]) throws
}

final class FileGoalRepository: GoalRepository {
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
                .appendingPathComponent("goals.json", isDirectory: false)
        }
    }
    
    func loadGoals() -> [Goal] {
        do {
            try ensureParentDir()
            guard fm.fileExists(atPath: url.path) else { return [] }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode([Goal].self, from: data)
            } catch {
                preserveCorruptFile()
                return []
            }
        } catch {
            return []
        }
    }
    
    func save(goals: [Goal]) throws {
        try ensureParentDir()
        let data = try encoder.encode(goals)
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
