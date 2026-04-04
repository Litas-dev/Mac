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
        var makeRootView: (() -> AnyView)?
        var layoutAttribute: NSLayoutConstraint.Attribute = .leading
        
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
        
        func attachIfNeeded(to window: NSWindow) {
            if self.window === window, controller != nil {
                return
            }
            detach()
            let hosting = NSHostingView(rootView: makeRootView?() ?? AnyView(EmptyView()))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            hosting.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            hosting.setContentHuggingPriority(.defaultHigh, for: .vertical)
            
            let controller = NSTitlebarAccessoryViewController()
            controller.view = hosting
            controller.layoutAttribute = layoutAttribute
            
            window.addTitlebarAccessoryViewController(controller)
            
            self.window = window
            self.controller = controller
            self.hosting = hosting
        }
    }
    
    final class AttachView: NSView {
        weak var coordinator: Coordinator?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            coordinator?.attachIfNeeded(to: window)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        context.coordinator.layoutAttribute = layout
        context.coordinator.makeRootView = { AnyView(content.environmentObject(store)) }
        let v = AttachView(frame: .zero)
        v.coordinator = context.coordinator
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.layoutAttribute = layout
        context.coordinator.makeRootView = { AnyView(content.environmentObject(store)) }
        if let window = nsView.window {
            context.coordinator.attachIfNeeded(to: window)
        }
        context.coordinator.hosting?.rootView = AnyView(content.environmentObject(store))
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }
    
    
}
#endif
