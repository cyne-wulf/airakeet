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
        allPermissionsGranted && modelReady
    }

    /// The checklist cares about the model being on disk; the engine itself
    /// is loaded on demand (and unloaded again after idling), so its
    /// in-memory status alone would show "not downloaded" after a relaunch.
    private var modelReady: Bool {
        switch controller.status {
        case .ready, .transcribing:
            return true
        case .loading, .error:
            return false
        case .idle:
            return controller.isModelDownloaded(controller.selectedTranscriptionModel)
        }
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
        VStack(alignment: .leading, spacing: 4) {
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

            if controller.permissions.migrationLikely {
                // Granted before but now revoked — almost always a stale entry
                // left behind when the app's signature changed across an update.
                // Offer a one-click fix instead of the manual hunt-and-remove.
                migrationBanner
            } else if !controller.permissions.hasAccessibilityPermission {
                // First-time setup, or a stale entry from a moved copy.
                Text("Already enabled? Remove any old Airakeet entry from the list, then add this copy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 34)
            }
        }
    }

    private var migrationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Looks like you updated Airakeet")
                .font(.caption)
                .fontWeight(.semibold)
            Text("Your old permission entry no longer matches this version. Click below to clear it and re-add Airakeet in one step.")
                .font(.caption2)
                .foregroundColor(.secondary)
            Button("Reset & re-add") {
                controller.permissions.resetAccessibilityEntry()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Text("This is a one-time step after updating — future updates won't ask again.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12))
        .cornerRadius(8)
        .padding(.leading, 34)
    }

    @ViewBuilder
    private var modelRow: some View {
        HStack {
            statusIcon(
                done: modelReady,
                failed: controller.status == .error
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Speech model")
                    .fontWeight(.bold)
                switch controller.status {
                case .idle:
                    Text(modelReady ? "Model ready" : "Downloads automatically (one time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                case .loading:
                    Group {
                        if let progress = controller.loadProgress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                        }
                    }
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
                if let progress = controller.loadProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
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
