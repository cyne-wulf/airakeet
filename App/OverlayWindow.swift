import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    static var shared: OverlayWindow?
    
    init(rootView: AnyView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true // Non-interfering
        
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView = hostingView
        
        centerOnScreen()
    }
    
    func centerOnScreen() {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = self.frame
            let x = (screenRect.width - windowRect.width) / 2
            let y = screenRect.origin.y + 100 // Bottom area
            self.setFrame(NSRect(x: x, y: y, width: windowRect.width, height: windowRect.height), display: true)
        }
    }
    
    static func show(view: AnyView) {
        if shared == nil {
            shared = OverlayWindow(rootView: view)
        }
        shared?.makeKeyAndOrderFront(nil)
        shared?.centerOnScreen()
    }
    
    static func hide() {
        shared?.orderOut(nil)
    }
}
