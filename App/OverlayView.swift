import SwiftUI
import Core

struct RecordingOverlayView: View {
    @ObservedObject var controller: AppController
    @State private var phase: Double = 0
    
    var body: some View {
        VStack(spacing: 12) {
            if controller.status == .transcribing {
                loadingView
            } else {
                waveformView
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                 removal: .opacity))
    }
    
    var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing...")
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
    
    var waveformView: some View {
        HStack(spacing: 4) {
            // Animated Waveform Bars
            ForEach(0..<8) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.gradient)
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: controller.currentPower)
            }
            
            Text("Listening...")
                .font(.system(.body, design: .rounded))
                .fontWeight(.bold)
                .padding(.leading, 8)
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let multiplier = CGFloat(controller.currentPower * 50)
        // Add some variation based on index
        let variation = sin(Double(index) + phase) * 2
        return min(24, max(base, base + multiplier + CGFloat(variation)))
    }
}

#Preview {
    ZStack {
        Color.gray.padding(100)
        RecordingOverlayView(controller: AppController())
    }
}
