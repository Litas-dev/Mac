import Foundation
import XCTest
@testable import PersonalFinancesApp

final class BillTests: XCTestCase {
    func testAdvanceMonthly() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 18))!
        let next = Recurrence.monthly.advance(from: start)
        let expected = cal.date(byAdding: .month, value: 1, to: start)!
        XCTAssertEqual(cal.component(.month, from: next), cal.component(.month, from: expected))
    }
}
