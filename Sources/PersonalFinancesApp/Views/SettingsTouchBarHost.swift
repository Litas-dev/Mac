import SwiftUI

#if os(macOS)
import AppKit

struct SettingsTouchBarHost: NSViewRepresentable {
    let selectedSection: String
    let onSelect: (String) -> Void
    
    func makeNSView(context: Context) -> SettingsTouchBarResponderView {
        let view = SettingsTouchBarResponderView()
        view.selectedSection = selectedSection
        view.onSelect = onSelect
        return view
    }
    
    func updateNSView(_ nsView: SettingsTouchBarResponderView, context: Context) {
        nsView.selectedSection = selectedSection
        nsView.onSelect = onSelect
        nsView.refresh()
    }
}

final class SettingsTouchBarResponderView: NSView, NSTouchBarDelegate {
    var selectedSection: String = ""
    var onSelect: ((String) -> Void)?
    
    private var customTouchBar: NSTouchBar?
    private var buttons: [String: NSButton] = [:]
    
    private let sections: [(id: String, title: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("appearance", "Appearance", "paintpalette"),
        ("notifications", "Alerts", "bell"),
        ("ai", "AI", "sparkles"),
        ("data", "Data", "externaldrive"),
        ("categories", "Categories", "tag"),
        ("budgets", "Budgets", "chart.pie")
    ]
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.customTouchBar == nil {
                self.customTouchBar = self.createTouchBar()
            }
            window.touchBar = self.customTouchBar
        }
    }
    
    private func createTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = sections.map { NSTouchBarItem.Identifier("pf.touchbar.settings.\($0.id)") }
        return bar
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let idString = identifier.rawValue.replacingOccurrences(of: "pf.touchbar.settings.", with: "")
        guard let section = sections.first(where: { $0.id == idString }) else { return nil }
        
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: section.title, target: self, action: #selector(buttonTapped(_:)))
        if let image = NSImage(systemSymbolName: section.icon, accessibilityDescription: nil) {
            button.image = image
            button.imagePosition = .imageLeft
        }
        button.identifier = NSUserInterfaceItemIdentifier(idString)
        button.bezelStyle = .rounded
        
        // Style selected
        if idString == selectedSection {
            button.bezelColor = .controlAccentColor
            button.contentTintColor = .white
        } else {
            button.bezelColor = .controlColor
            button.contentTintColor = nil
        }
        
        buttons[idString] = button
        item.view = button
        return item
    }
    
    func refresh() {
        for (id, button) in buttons {
            if id == selectedSection {
                button.bezelColor = .controlAccentColor
                button.contentTintColor = .white
            } else {
                button.bezelColor = .controlColor
                button.contentTintColor = nil
            }
        }
    }
    
    @objc private func buttonTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onSelect?(id)
    }
}
#endif
