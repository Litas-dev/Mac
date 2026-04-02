import Foundation

enum Recurrence: String, Codable, CaseIterable, Hashable {
    case once
    case weekly
    case monthly
    case yearly

    func advance(from date: Date, by count: Int = 1) -> Date {
        let cal = Calendar.current
        switch self {
        case .once:
            return date
        case .weekly:
            return cal.date(byAdding: .weekOfYear, value: count, to: date) ?? date
        case .monthly:
            return cal.date(byAdding: .month, value: count, to: date) ?? date
        case .yearly:
            return cal.date(byAdding: .year, value: count, to: date) ?? date
        }
    }
}
