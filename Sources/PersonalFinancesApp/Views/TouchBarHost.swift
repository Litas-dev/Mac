import SwiftUI

#if os(macOS)
import AppKit

struct TouchBarHost: NSViewRepresentable {
    let title: String
    let isEnabled: Bool
    let bezelColor: NSColor
    let titleColor: NSColor
    let onTap: () -> Void
    
    func makeNSView(context: Context) -> TouchBarResponderView {
        let view = TouchBarResponderView()
        view.onTap = onTap
        view.titleText = title
        view.isEnabled = isEnabled
        view.bezelColor = bezelColor
        view.titleColor = titleColor
        return view
    }
    
    func updateNSView(_ nsView: TouchBarResponderView, context: Context) {
        nsView.onTap = onTap
        nsView.titleText = title
        nsView.isEnabled = isEnabled
        nsView.bezelColor = bezelColor
        nsView.titleColor = titleColor
        nsView.refresh()
    }
}

final class TouchBarResponderView: NSView, NSTouchBarDelegate {
    var onTap: (() -> Void)?
    var titleText: String = "Next Bill"
    var isEnabled: Bool = true
    var bezelColor: NSColor = .controlAccentColor
    var titleColor: NSColor = .white
    
    private let nextBillID = NSTouchBarItem.Identifier("pf.touchbar.nextDueBill")
    private weak var button: NSButton?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
    
    override func makeTouchBar() -> NSTouchBar? {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [nextBillID]
        return bar
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == nextBillID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: titleText, target: self, action: #selector(tapped))
        button.bezelColor = bezelColor
        button.bezelStyle = .rounded
        button.isEnabled = isEnabled
        button.attributedTitle = NSAttributedString(string: titleText, attributes: [.foregroundColor: titleColor])
        item.view = button
        self.button = button
        return item
    }
    
    func refresh() {
        button?.title = titleText
        button?.isEnabled = isEnabled
        button?.bezelColor = bezelColor
        if let button {
            button.attributedTitle = NSAttributedString(string: titleText, attributes: [.foregroundColor: titleColor])
        }
    }
    
    @objc private func tapped() {
        onTap?()
    }
}
#endif
