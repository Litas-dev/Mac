import Foundation

struct Goal: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var targetAmount: DecimalAmount
    var savedAmount: DecimalAmount
    var targetDate: Date? = nil
    var notes: String? = nil
    var archived: Bool = false
}

