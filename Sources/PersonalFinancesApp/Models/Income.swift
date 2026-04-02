import Foundation

struct Income: Identifiable, Hashable, Codable {
    enum Source: String, Codable, CaseIterable {
        case salary, freelance, rental, investment, other
    }
    var id: UUID = UUID()
    var name: String
    var amount: DecimalAmount
    var source: Source
    var customSourceName: String? = nil
    var recurrence: Recurrence
    var nextPayDate: Date
    var notes: String?
    var receipts: [Payment] = []
    
    mutating func logReceipt(on date: Date = Date(), amount: DecimalAmount? = nil) {
        receipts.append(.init(date: date, amount: amount ?? self.amount))
        nextPayDate = recurrence.advance(from: nextPayDate)
    }
}
