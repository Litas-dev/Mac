import Foundation

protocol BillRepository {
    func loadBills() -> [Bill]
    func save(bills: [Bill]) throws
}

final class InMemoryBillRepository: BillRepository {
    private var storage: [Bill]

    init(seed: Bool = true) {
        if seed {
            self.storage = SeedData.sampleBills
        } else {
            self.storage = []
        }
    }

    func loadBills() -> [Bill] {
        storage
    }

    func save(bills: [Bill]) throws {
        storage = bills
    }
}

enum SeedData {
    static var sampleBills: [Bill] {
        let now = Date()
        return [
            Bill(
                name: "Mortgage",
                amount: .init(currencyCode: "NOK", value: 9500),
                category: .housing,
                recurrence: .monthly,
                nextDueDate: Calendar.current.date(byAdding: .day, value: 13, to: now) ?? now,
                notes: "Every month on the 1st"
            ),
            Bill(
                name: "Electricity",
                amount: .init(currencyCode: "NOK", value: 499),
                category: .utilities,
                recurrence: .monthly,
                nextDueDate: Calendar.current.date(byAdding: .day, value: 31, to: now) ?? now,
                notes: "Auto-debit"
            )
        ]
    }
}

