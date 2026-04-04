import SwiftUI

#if os(macOS)
import AppKit

struct TitlebarAccessoryHost<Content: View>: NSViewRepresentable {
    @EnvironmentObject private var store: AppStore
    let layout: NSLayoutConstraint.Attribute
    let content: Content
    
    init(layout: NSLayoutConstraint.Attribute = .leading, @ViewBuilder content: () -> Content) {
        self.layout = layout
        self.content = content()
    }
    
    final class Coordinator {
        weak var window: NSWindow?
        var controller: NSTitlebarAccessoryViewController?
        var hosting: NSHostingView<AnyView>?
        
        func detach() {
            if let window, let controller {
                if let idx = window.titlebarAccessoryViewControllers.firstIndex(of: controller) {
                    window.removeTitlebarAccessoryViewController(at: idx)
                }
            }
            window = nil
            controller = nil
            hosting = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            attachIfNeeded(nsView: v, context: context)
        }
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            attachIfNeeded(nsView: nsView, context: context)
            context.coordinator.hosting?.rootView = AnyView(content.environmentObject(store))
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }
    
    private func attachIfNeeded(nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if context.coordinator.window === window, context.coordinator.controller != nil {
            return
        }
        
        context.coordinator.detach()
        
        let hosting = NSHostingView(rootView: AnyView(content.environmentObject(store)))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hosting.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        let controller = NSTitlebarAccessoryViewController()
        controller.view = hosting
        controller.layoutAttribute = layout
        
        window.addTitlebarAccessoryViewController(controller)
        
        context.coordinator.window = window
        context.coordinator.controller = controller
        context.coordinator.hosting = hosting
    }
}
#endif
