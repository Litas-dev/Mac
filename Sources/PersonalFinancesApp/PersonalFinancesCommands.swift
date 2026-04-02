import SwiftUI
import AppKit

struct PersonalFinancesCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    private var aboutVersionString: String {
        let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        if short.isEmpty { return "" }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Personal Finances") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationVersion: aboutVersionString
                ])
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        CommandGroup(after: .help) {
            Button("Help…") {
                openWindow(id: "help")
            }
        }
    }
}
