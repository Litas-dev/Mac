import Foundation

extension Income.Source {
    var defaultRecurrence: Recurrence {
        switch self {
        case .salary: return .monthly
        case .freelance: return .once
        case .rental: return .monthly
        case .investment: return .once
        case .other: return .once
        }
    }
}
