import SwiftUI

#if os(macOS)
import AppKit

struct TouchBarHost: NSViewRepresentable {
    let title: String
    let isEnabled: Bool
    let bezelColor: NSColor
    let titleColor: NSColor
    let onTap: () -> Void
    var onEditTap: (() -> Void)? = nil
    var onPayTap: (() -> Void)? = nil
    var onSnooze1: (() -> Void)? = nil
    var onSnooze3: (() -> Void)? = nil
    var onSnoozeWeek: (() -> Void)? = nil
    var onReportsTap: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> TouchBarResponderView {
        let view = TouchBarResponderView()
        view.onTap = onTap
        view.onEditTap = onEditTap
        view.onPayTap = onPayTap
        view.onSnooze1 = onSnooze1
        view.onSnooze3 = onSnooze3
        view.onSnoozeWeek = onSnoozeWeek
        view.onReportsTap = onReportsTap
        view.titleText = title
        view.isEnabled = isEnabled
        view.bezelColor = bezelColor
        view.titleColor = titleColor
        return view
    }
    
    func updateNSView(_ nsView: TouchBarResponderView, context: Context) {
        nsView.onTap = onTap
        nsView.onEditTap = onEditTap
        nsView.onPayTap = onPayTap
        nsView.onSnooze1 = onSnooze1
        nsView.onSnooze3 = onSnooze3
        nsView.onSnoozeWeek = onSnoozeWeek
        nsView.onReportsTap = onReportsTap
        nsView.titleText = title
        nsView.isEnabled = isEnabled
        nsView.bezelColor = bezelColor
        nsView.titleColor = titleColor
        nsView.refresh()
    }
}

final class TouchBarResponderView: NSView, NSTouchBarDelegate {
    var onTap: (() -> Void)?
    var onEditTap: (() -> Void)?
    var onPayTap: (() -> Void)?
    var onSnooze1: (() -> Void)?
    var onSnooze3: (() -> Void)?
    var onSnoozeWeek: (() -> Void)?
    var onReportsTap: (() -> Void)?
    var titleText: String = "Next Bill"
    var isEnabled: Bool = true
    var bezelColor: NSColor = .controlAccentColor
    var titleColor: NSColor = .white
    
    private let nextBillID = NSTouchBarItem.Identifier("pf.touchbar.nextDueBill")
    private let editBillID = NSTouchBarItem.Identifier("pf.touchbar.editBill")
    private let payBillID = NSTouchBarItem.Identifier("pf.touchbar.payBill")
    private let snooze1ID = NSTouchBarItem.Identifier("pf.touchbar.snooze1")
    private let snooze3ID = NSTouchBarItem.Identifier("pf.touchbar.snooze3")
    private let snoozeWeekID = NSTouchBarItem.Identifier("pf.touchbar.snoozeWeek")
    private let reportsID = NSTouchBarItem.Identifier("pf.touchbar.reports")
    
    private weak var button: NSButton?
    private weak var editButton: NSButton?
    private weak var payButton: NSButton?
    private weak var snooze1Button: NSButton?
    private weak var snooze3Button: NSButton?
    private weak var snoozeWeekButton: NSButton?
    private weak var reportsButton: NSButton?
    
    private var customTouchBar: NSTouchBar?
    
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
        var items: [NSTouchBarItem.Identifier] = [nextBillID]
        if onEditTap != nil { items.append(editBillID) }
        if onPayTap != nil { items.append(payBillID) }
        if onSnooze1 != nil { items.append(snooze1ID) }
        if onSnooze3 != nil { items.append(snooze3ID) }
        if onSnoozeWeek != nil { items.append(snoozeWeekID) }
        if onReportsTap != nil {
            items.append(.flexibleSpace)
            items.append(reportsID)
        }
        bar.defaultItemIdentifiers = items
        return bar
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == nextBillID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: titleText, target: self, action: #selector(tapped))
            if bezelColor == .controlColor {
                // For "Cancel" / neutral buttons, don't force text to white
                button.bezelColor = bezelColor
                button.bezelStyle = .rounded
                button.isEnabled = isEnabled
                button.title = titleText
            } else {
                button.bezelColor = bezelColor
                button.bezelStyle = .rounded
                button.isEnabled = isEnabled
                button.attributedTitle = NSAttributedString(string: titleText, attributes: [.foregroundColor: titleColor])
            }
            item.view = button
            self.button = button
            return item
        } else if identifier == editBillID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "Edit", target: self, action: #selector(editTapped))
            button.bezelStyle = .rounded
            button.isEnabled = isEnabled && onEditTap != nil
            item.view = button
            self.editButton = button
            return item
        } else if identifier == payBillID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "Log Payment", target: self, action: #selector(payTapped))
            button.bezelColor = .systemBlue
            button.bezelStyle = .rounded
            button.isEnabled = isEnabled && onPayTap != nil
            button.attributedTitle = NSAttributedString(string: "Log Payment", attributes: [.foregroundColor: NSColor.white])
            item.view = button
            self.payButton = button
            return item
        } else if identifier == snooze1ID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "+1 Day", target: self, action: #selector(snooze1Tapped))
            button.bezelStyle = .rounded
            button.isEnabled = isEnabled && onSnooze1 != nil
            item.view = button
            self.snooze1Button = button
            return item
        } else if identifier == snooze3ID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "+3 Days", target: self, action: #selector(snooze3Tapped))
            button.bezelStyle = .rounded
            button.isEnabled = isEnabled && onSnooze3 != nil
            item.view = button
            self.snooze3Button = button
            return item
        } else if identifier == snoozeWeekID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "Next Week", target: self, action: #selector(snoozeWeekTapped))
            button.bezelStyle = .rounded
            button.isEnabled = isEnabled && onSnoozeWeek != nil
            item.view = button
            self.snoozeWeekButton = button
            return item
        } else if identifier == reportsID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "Reports", target: self, action: #selector(reportsTapped))
            if let image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil) {
                button.image = image
                button.imagePosition = .imageLeft
            }
            button.bezelStyle = .rounded
            button.isEnabled = onReportsTap != nil
            item.view = button
            self.reportsButton = button
            return item
        }
        return nil
    }
    
    func refresh() {
        button?.title = titleText
        button?.isEnabled = isEnabled
        if bezelColor == .controlColor {
            button?.bezelColor = bezelColor
            button?.attributedTitle = NSAttributedString(string: titleText)
        } else {
            button?.bezelColor = bezelColor
            button?.attributedTitle = NSAttributedString(string: titleText, attributes: [.foregroundColor: titleColor])
        }
        
        editButton?.isEnabled = isEnabled && onEditTap != nil
        payButton?.isEnabled = isEnabled && onPayTap != nil
        snooze1Button?.isEnabled = isEnabled && onSnooze1 != nil
        snooze3Button?.isEnabled = isEnabled && onSnooze3 != nil
        snoozeWeekButton?.isEnabled = isEnabled && onSnoozeWeek != nil
        reportsButton?.isEnabled = onReportsTap != nil
        
        var items: [NSTouchBarItem.Identifier] = [nextBillID]
        if onEditTap != nil { items.append(editBillID) }
        if onPayTap != nil { items.append(payBillID) }
        if onSnooze1 != nil { items.append(snooze1ID) }
        if onSnooze3 != nil { items.append(snooze3ID) }
        if onSnoozeWeek != nil { items.append(snoozeWeekID) }
        if onReportsTap != nil {
            items.append(.flexibleSpace)
            items.append(reportsID)
        }
        
        if customTouchBar?.defaultItemIdentifiers != items {
            customTouchBar?.defaultItemIdentifiers = items
        }
    }
    
    @objc private func tapped() { onTap?() }
    @objc private func editTapped() { onEditTap?() }
    @objc private func payTapped() { onPayTap?() }
    @objc private func snooze1Tapped() { onSnooze1?() }
    @objc private func snooze3Tapped() { onSnooze3?() }
    @objc private func snoozeWeekTapped() { onSnoozeWeek?() }
    @objc private func reportsTapped() { onReportsTap?() }
}
#endif
