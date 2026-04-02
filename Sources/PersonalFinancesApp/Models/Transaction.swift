import Foundation

struct Transaction: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case expense, income, transfer
    }
    
    var id: UUID = UUID()
    var kind: Kind
    var date: Date
    var amount: DecimalAmount
    
    var accountId: UUID? = nil
    var toAccountId: UUID? = nil
    
    var category: Bill.Category? = nil
    var customCategoryName: String? = nil
    
    var payee: String? = nil
    var notes: String? = nil
    var tags: [String] = []
    
    var relatedBillId: UUID? = nil
    var relatedIncomeId: UUID? = nil
}

