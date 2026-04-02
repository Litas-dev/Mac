import SwiftUI

#if os(macOS)
import AppKit

struct WindowDraggableModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowAccessor { window in
                window?.isMovableByWindowBackground = true
            })
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func draggableWindow() -> some View {
        self.modifier(WindowDraggableModifier())
    }
}
#endif
