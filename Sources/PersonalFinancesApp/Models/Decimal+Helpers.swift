import Foundation

extension Decimal {
    func doubleValueRounded(_ places: Int) -> Double {
        var d = self
        var result = Decimal()
        NSDecimalRound(&result, &d, places, .plain)
        return (result as NSDecimalNumber).doubleValue
    }
}
