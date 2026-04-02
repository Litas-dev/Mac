import SwiftUI

struct PersonalFinancesCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Help…") {
                openWindow(id: "help")
            }
        }
    }
}
