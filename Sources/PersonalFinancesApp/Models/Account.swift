import Foundation

struct Account: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case checking, savings, credit, cash, investment, other
    }
    
    var id: UUID = UUID()
    var name: String
    var kind: Kind
    var currencyCode: String
    var openingBalance: Decimal = 0
    var institution: String? = nil
    var notes: String? = nil
    var archived: Bool = false
}

