import Foundation

struct Payment: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var date: Date
    var amount: DecimalAmount
}

