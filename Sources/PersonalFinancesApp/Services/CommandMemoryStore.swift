import Foundation

struct CommandMemoryEntry: Codable, Identifiable {
    let id: UUID
    var input: String
    var command: AIParsedCommand
    var count: Int
    var lastUsed: Date
    var favorite: Bool
}

final class CommandMemoryStore {
    static let shared = CommandMemoryStore()
    private let queue = DispatchQueue(label: "pf.commandmemory")
    private var entries: [CommandMemoryEntry] = []
    private let limit = 200
    private init() { load() }
    
    func record(input: String, command: AIParsedCommand, favorite: Bool = false) {
        queue.sync {
            let key = normalize(input: input)
            if let idx = entries.firstIndex(where: { normalize(input: $0.input) == key && $0.command.type == command.type }) {
                entries[idx].count += 1
                entries[idx].lastUsed = Date()
                if favorite { entries[idx].favorite = true }
            } else {
                let e = CommandMemoryEntry(id: UUID(), input: input, command: command, count: 1, lastUsed: Date(), favorite: favorite)
                entries.insert(e, at: 0)
                if entries.count > limit { entries.removeLast(entries.count - limit) }
            }
            save()
        }
    }
    
    func toggleFavorite(id: UUID) {
        queue.sync {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].favorite.toggle()
            save()
        }
    }
    
    func recents(limit: Int = 6) -> [CommandMemoryEntry] {
        queue.sync {
            let favs = entries.filter { $0.favorite }.sorted { $0.lastUsed > $1.lastUsed }.prefix(3)
            let rec = entries.sorted { $0.lastUsed > $1.lastUsed }.prefix(limit)
            var merged: [CommandMemoryEntry] = []
            var seen = Set<UUID>()
            for e in favs { merged.append(e); seen.insert(e.id) }
            for e in rec where !seen.contains(e.id) { merged.append(e) }
            return Array(merged.prefix(limit))
        }
    }
    
    func suggestions(for text: String, limit: Int = 6) -> [CommandMemoryEntry] {
        let tokens = normalizeTokens(text: text)
        if tokens.isEmpty { return recents(limit: limit) }
        return queue.sync {
            let scored = entries.map { e -> (CommandMemoryEntry, Int) in
                let et = normalizeTokens(text: e.input)
                let score = tokens.reduce(0) { $0 + (et.contains($1) ? 1 : 0) } + e.count + (e.favorite ? 3 : 0)
                return (e, score)
            }
            return scored.sorted { a, b in
                if a.1 == b.1 { return a.0.lastUsed > b.0.lastUsed }
                return a.1 > b.1
            }.prefix(limit).map { $0.0 }
        }
    }
    
    private func normalize(input: String) -> String {
        input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " ")
    }
    private func normalizeTokens(text: String) -> [String] {
        normalize(input: text).split(separator: " ").map { String($0) }
    }
    
    private func fileURL() -> URL {
        let fm = FileManager.default
        let dir = PersistencePaths.localBaseDirectory()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CommandMemory.json")
    }
    
    private func legacyFileURL() -> URL {
        PersistencePaths.legacyLocalBaseDirectory()
            .appendingPathComponent("CommandMemory.json")
    }
    
    private func load() {
        let url = fileURL()
        let data: Data?
        if let d = try? Data(contentsOf: url) {
            data = d
        } else if let d = try? Data(contentsOf: legacyFileURL()) {
            data = d
        } else {
            data = nil
        }
        guard let data else { return }
        if let decoded = try? JSONDecoder().decode([CommandMemoryEntry].self, from: data) {
            entries = decoded
            save()
            return
        }
        let df = ISO8601DateFormatter()
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(df.string(from: Date()))")
            .appendingPathExtension("json")
        _ = try? FileManager.default.copyItem(at: url, to: backupURL)
    }
    private func save() {
        let url = fileURL()
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
