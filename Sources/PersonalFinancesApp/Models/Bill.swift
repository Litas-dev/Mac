import Foundation

struct BillAttachment: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var displayName: String
    var storedRelativePath: String
    var createdAt: Date = Date()
}

struct Bill: Identifiable, Hashable, Codable {
    enum Category: String, Codable, CaseIterable {
        case housing, utilities, subscriptions, insurance, taxes, transport, other
    }

    var id: UUID = UUID()
    var name: String
    var amount: DecimalAmount
    var category: Category
    var customCategoryName: String? = nil
    var recurrence: Recurrence
    var nextDueDate: Date
    var notes: String?
    var payments: [Payment] = []
    var paidAutomatically: Bool = false
    var hiddenUntilEdited: Bool = false
    var snoozeUntil: Date? = nil
    var snoozeCount: Int = 0
    var attachments: [BillAttachment] = []

    var isOverdue: Bool {
        Date() > nextDueDate && !isPaidFor(date: nextDueDate)
    }
    
    var isSnoozedActive: Bool {
        if let s = snoozeUntil { return s > Date() }
        return false
    }

    func isPaidFor(date: Date) -> Bool {
        if recurrence == .once {
            return !payments.isEmpty
        }
        // A bill is "paid for" a specific due date if there is any payment made 
        // within a reasonable window around that date, or if it was marked paid
        // and the nextDueDate has already advanced past this date.
        // For simplicity in this app's current logic: we check if any payment exists
        // that falls between the previous cycle's due date and the current nextDueDate.
        
        let cal = Calendar.current
        let prevDue = recurrence.advance(from: date, by: -1)
        
        return payments.contains { p in
            let pDate = cal.startOfDay(for: p.date)
            // A payment counts if it was made after the previous due date 
            // and before or on the target due date (with some grace period)
            return pDate > cal.startOfDay(for: prevDue) && pDate <= cal.startOfDay(for: date)
        }
    }

    mutating func markPaid(on date: Date = Date(), amount: DecimalAmount? = nil) {
        if recurrence == .once, !payments.isEmpty {
            return
        }
        let payment = Payment(date: date, amount: amount ?? self.amount)
        payments.append(payment)
        nextDueDate = recurrence.advance(from: nextDueDate)
    }
    
    mutating func setSnooze(until date: Date) {
        snoozeUntil = date
        snoozeCount += 1
    }
    
    mutating func clearSnooze() {
        snoozeUntil = nil
    }
}

struct DecimalAmount: Hashable, Codable {
    var currencyCode: String
    var value: Decimal
}
