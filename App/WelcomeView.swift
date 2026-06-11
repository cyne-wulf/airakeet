import SwiftUI
import KeyboardShortcuts
import Core

/// One-time setup window shown on first launch (and reachable from the
/// menubar as "Setup Guide..."). Walks a new user through the two required
/// permissions and shows the speech model download, all driven by state
/// AppController already publishes.
struct WelcomeView: View {
    @ObservedObject var controller: AppController

    private var allPermissionsGranted: Bool {
        controller.permissions.hasMicrophonePermission && controller.permissions.hasAccessibilityPermission
    }

    private var isReadyToDictate: Bool {
        allPermissionsGranted && (controller.status == .ready || controller.status == .transcribing)
    }

    private var hotkeyDisplay: String {
        guard KeyboardShortcutsSupport.bundlePresent,
              let shortcut = KeyboardShortcuts.getShortcut(for: .toggleAirakeet) else {
            return "Fn + `"
        }
        return shortcut.description
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            hotkeyCallout

            VStack(alignment: .leading, spacing: 10) {
                Text("SETUP CHECKLIST")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                microphoneRow
                accessibilityRow
                modelRow
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .cornerRadius(12)

            tryItHint

            Spacer(minLength: 0)

            Button("Done") {
                WelcomeWindow.shared?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Reopen anytime from the menubar → Setup Guide")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(26)
        .frame(width: 440, height: 560)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(controller.waveformColor)
            Text("Welcome to Airakeet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Press the hotkey, speak, press again — your words are typed wherever your cursor is.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var hotkeyCallout: some View {
        HStack {
            Image(systemName: "keyboard")
                .foregroundColor(.secondary)
            Text("Your hotkey:")
                .foregroundColor(.secondary)
            Text(hotkeyDisplay)
                .fontWeight(.bold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
            Spacer()
            Button("Change…") {
                controller.openSettingsWindow()
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 4)
    }

    private var microphoneRow: some View {
        checklistRow(
            label: "Microphone",
            detail: "Lets Airakeet hear you.",
            granted: controller.permissions.hasMicrophonePermission
        ) {
            Button("Grant") {
                Task { _ = await controller.permissions.requestMicrophone() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var accessibilityRow: some View {
        checklistRow(
            label: "Accessibility",
            detail: "Lets Airakeet type for you.",
            granted: controller.permissions.hasAccessibilityPermission
        ) {
            HStack(spacing: 6) {
                Button("Grant") {
                    controller.permissions.requestAccessibility()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Open System Settings") {
                    controller.permissions.openSystemSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var modelRow: some View {
        HStack {
            statusIcon(
                done: controller.status == .ready || controller.status == .transcribing,
                failed: controller.status == .error
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Speech model")
                    .fontWeight(.bold)
                switch controller.status {
                case .idle:
                    Text("Downloads automatically (one time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                case .loading:
                    ProgressView(value: controller.loadProgress)
                        .frame(maxWidth: 180)
                case .ready, .transcribing:
                    Text("Model ready")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                case .error:
                    Text("Download failed")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            if controller.status == .loading {
                Text("\(Int(controller.loadProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            } else if controller.status == .error {
                Button("Retry") {
                    controller.loadModel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var tryItHint: some View {
        HStack {
            Image(systemName: isReadyToDictate ? "sparkles" : "hourglass")
            Text(isReadyToDictate
                 ? "You're set! Click into any text field and press \(hotkeyDisplay)."
                 : "Finish the checklist above, then dictate anywhere.")
                .font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background((isReadyToDictate ? controller.waveformColor : Color.secondary).opacity(0.12))
        .cornerRadius(10)
        .opacity(isReadyToDictate ? 1 : 0.7)
    }

    private func checklistRow(label: String, detail: String, granted: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            statusIcon(done: granted, failed: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.bold)
                Text(granted ? "Granted" : detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !granted {
                action()
            }
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(done: Bool, failed: Bool) -> some View {
        Image(systemName: failed ? "exclamationmark.triangle.fill" : (done ? "checkmark.circle.fill" : "circle"))
            .foregroundColor(failed ? .red : (done ? .green : .secondary))
            .font(.title3)
            .frame(width: 24)
    }
}

class WelcomeWindow: NSWindow {
    static var shared: WelcomeWindow?

    static func show(controller: AppController) {
        NSApp.activate(ignoringOtherApps: true)

        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }

        let window = WelcomeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to Airakeet"
        window.contentView = NSHostingView(rootView: WelcomeView(controller: controller))
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate.shared
        window.makeKeyAndOrderFront(nil)
        shared = window
    }

    @MainActor
    private class WindowDelegate: NSObject, NSWindowDelegate {
        static let shared = WindowDelegate()

        func windowWillClose(_ notification: Notification) {
            if let window = notification.object as? WelcomeWindow, window === WelcomeWindow.shared {
                WelcomeWindow.shared = nil
            }
        }
    }
}
