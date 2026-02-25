import SwiftUI
import AppKit

struct UpdateStatusView: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        VStack(spacing: 20) {
            header
            statusDetails
            progressSection
            releaseNotesSection
            actionButtons
        }
        .padding(24)
        .frame(width: 360, height: 420)
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(controller.updateStatus.isBusy ? .blue : .secondary)
            VStack(alignment: .leading) {
                Text("Airakeet Updates")
                    .font(.headline)
                Text("Current version \(controller.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    private var statusDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.title3)
                .fontWeight(.semibold)
            Text(statusSubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.updateStatus.isBusy {
                ProgressView(value: controller.updateStatus.progressValue ?? 0, total: 1)
                    .progressViewStyle(.linear)
                if let percent = controller.updateStatus.progressValue.map({ Int($0 * 100) }) {
                    Text("\(percent)% downloaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .hidden()
            }
        }
    }
    
    private var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LATEST RELEASE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                if let version = controller.latestRelease?.normalizedVersion {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ScrollView {
                Text(controller.latestRelease?.body ?? "Release notes will appear once a new version is found.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
            }
            .frame(height: 160)
            .padding(8)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)
        }
    }
    
    private var actionButtons: some View {
        HStack {
            Spacer()
            switch controller.updateStatus {
            case .needsRestart:
                Button("Restart Now") {
                    controller.restartAfterUpdate()
                }
                .buttonStyle(.borderedProminent)
                Button("Later") {
                    UpdateStatusWindow.shared?.close()
                }
                .buttonStyle(.bordered)
            case .failed:
                Button("Retry") {
                    controller.beginUpdateFlow()
                }
                .buttonStyle(.borderedProminent)
                Button("Close") {
                    UpdateStatusWindow.shared?.close()
                }
                .buttonStyle(.bordered)
            default:
                Button("Close") {
                    UpdateStatusWindow.shared?.close()
                }
                .buttonStyle(.bordered)
                .disabled(controller.updateStatus.isBusy)
            }
        }
    }
    
    private var statusTitle: String {
        switch controller.updateStatus {
        case .idle:
            return "Ready to Check"
        case .checking:
            return "Checking GitHub Releases..."
        case .downloading:
            return "Downloading Update"
        case .installing:
            return "Installing"
        case .upToDate(let remote):
            return "You're up to date (v\(remote))"
        case .needsRestart(let version):
            return "Update Ready (v\(version))"
        case .failed:
            return "Update Failed"
        }
    }
    
    private var statusSubtitle: String {
        switch controller.updateStatus {
        case .idle:
            return "Click the button in the menu bar to check for new releases."
        case .checking:
            return "Fetching the latest version from GitHub."
        case .downloading:
            return "A new release is being downloaded securely."
        case .installing:
            return "Airakeet is replacing the old app bundle."
        case .upToDate:
            return "No download needed. We'll stay idle until you check again."
        case .needsRestart:
            return "Restart to finish installing the latest version."
        case .failed(let message):
            return message
        }
    }
}

@MainActor
class UpdateStatusWindow: NSWindow {
    static var shared: UpdateStatusWindow?
    
    static func show(controller: AppController) {
        if let existing = shared {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = UpdateStatusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Airakeet Updates"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateStatusView(controller: controller))
        window.makeKeyAndOrderFront(nil)
        window.delegate = WindowDelegate.shared
        UpdateStatusWindow.shared = window
    }
    
    @MainActor
    private class WindowDelegate: NSObject, NSWindowDelegate {
        static let shared = WindowDelegate()
        
        func windowWillClose(_ notification: Notification) {
            if let window = notification.object as? UpdateStatusWindow, window === UpdateStatusWindow.shared {
                UpdateStatusWindow.shared = nil
            }
        }
    }
}
