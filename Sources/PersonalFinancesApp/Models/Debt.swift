import Foundation

struct Debt: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case creditCard, loan, mortgage, other
    }
    
    var id: UUID = UUID()
    var name: String
    var kind: Kind
    var currencyCode: String
    var principal: Decimal
    var annualInterestRate: Decimal
    var minimumPayment: Decimal
    var dueDayOfMonth: Int? = nil
    var notes: String? = nil
    var archived: Bool = false
}

