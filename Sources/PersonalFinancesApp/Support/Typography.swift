import SwiftUI

enum Typography {
    static func amountFont(for settings: AppSettings) -> Font {
        switch settings.textSize {
        case .small: return .body.monospacedDigit()
        case .normal: return .title3.monospacedDigit()
        case .large: return .title2.monospacedDigit()
        }
    }
    static func sectionTitleFont(for settings: AppSettings) -> Font {
        switch settings.textSize {
        case .small: return .headline
        case .normal: return .title3
        case .large: return .title2
        }
    }
    static func buttonFont(for settings: AppSettings) -> Font {
        switch settings.textSize {
        case .small: return .subheadline
        case .normal: return .body
        case .large: return .headline
        }
    }
}
