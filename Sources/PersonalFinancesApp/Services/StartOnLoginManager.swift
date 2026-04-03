import Foundation

final class StartOnLoginManager {
    static let shared = StartOnLoginManager()
    private init() {}
    
    private let label = "com.personalfinances.startonlogin"
    
    func apply(enabled: Bool) {
        DispatchQueue.global(qos: .utility).async {
            do {
                if enabled {
                    try self.installLaunchAgent()
                    try self.loadAgent()
                } else {
                    try self.unloadAgent()
                    try self.removeLaunchAgent()
                }
            } catch {
                return
            }
        }
    }
    
    private func launchAgentsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }
    
    private func plistURL() -> URL {
        launchAgentsURL().appendingPathComponent("\(label).plist")
    }
    
    private func installLaunchAgent() throws {
        try FileManager.default.createDirectory(at: launchAgentsURL(), withIntermediateDirectories: true)
        let execPath = Bundle.main.executableURL?.path ?? (Bundle.main.bundlePath + "/Contents/MacOS/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "Kivana"))
        let dict: [String: Any] = [
            "Label": label,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProgramArguments": [execPath]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL(), options: .atomic)
    }
    
    private func removeLaunchAgent() throws {
        if FileManager.default.fileExists(atPath: plistURL().path) {
            try FileManager.default.removeItem(at: plistURL())
        }
    }
    
    private func loadAgent() throws {
        runLaunchctl(["load", "-w", plistURL().path])
    }
    
    private func unloadAgent() throws {
        runLaunchctl(["unload", "-w", plistURL().path])
    }
    
    private func runLaunchctl(_ arguments: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = arguments
        try? proc.run()
        proc.waitUntilExit()
    }
}
