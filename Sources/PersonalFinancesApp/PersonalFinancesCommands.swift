import SwiftUI

struct KivanaCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    #if DEBUG
    @AppStorage("debugShowLayoutGrid") private var debugShowLayoutGrid: Bool = false
    #endif
    
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Help…") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: [.command])
        }
        #if DEBUG
        CommandMenu("Debug") {
            Toggle("Layout Grid", isOn: $debugShowLayoutGrid)
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }
        #endif
    }
}
