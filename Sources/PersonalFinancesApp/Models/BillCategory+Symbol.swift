import Foundation

extension Bill.Category {
    var symbolName: String {
        switch self {
        case .housing: return "house"
        case .utilities: return "bolt"
        case .subscriptions: return "play.rectangle"
        case .insurance: return "shield.checkered"
        case .taxes: return "banknote"
        case .transport: return "car"
        case .other: return "circle.grid.2x2"
        }
    }
}
