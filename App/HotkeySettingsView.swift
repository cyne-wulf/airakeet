import SwiftUI
import KeyboardShortcuts
import Core

struct HotkeySettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                Text("Launch Shortcut")
                    .font(.headline)
                Spacer()
            }
            
            Text("Choose a global hotkey to start/stop dictation from anywhere.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Shortcut:")
                    KeyboardShortcuts.Recorder(for: .toggleAirakeet)
                        .fixedSize()
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Button("Reset to Default (Fn + `)") {
                    KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.backtick, modifiers: [.function]), for: .toggleAirakeet)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            
            Text("Tip: Try using 'Option + Space' or 'Cmd + Shift + L'.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Note: Some keys like 'Fn' can only be set via the Reset button.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
            
            Button("Done") {
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 400)
    }
}

class HotkeySettingsWindow: NSWindow {
    static var shared: HotkeySettingsWindow?
    
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = HotkeySettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Airakeet Hotkey"
        window.contentView = NSHostingView(rootView: HotkeySettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        shared = window
    }
}
