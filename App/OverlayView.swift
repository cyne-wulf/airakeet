import SwiftUI
import Core

struct RecordingOverlayView: View {
    @ObservedObject var controller: AppController
    @State private var phase: Double = 0
    
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 16) {
            if controller.status == .transcribing {
                loadingView
            } else {
                waveformView
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56) // FIXED HEIGHT to stop jiggling
        .background {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.05)) {
                phase += 0.5
            }
        }
    }
    
    var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing...")
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .fixedSize() // Prevents text from being cut off
        }
    }
    
    var waveformView: some View {
        HStack(alignment: .center, spacing: 3) {
            // Animated Waveform Bars
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<12) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(controller.waveformColor.gradient)
                        .frame(width: 3, height: barHeight(for: i))
                        .animation(.spring(response: 0.15, dampingFraction: 0.4), value: controller.currentPower)
                        .animation(.linear(duration: 0.05), value: phase)
                }
            }
            .frame(width: 75) // Fixed width for bar area
            
            Text("Listening...")
                .font(.system(.body, design: .rounded))
                .fontWeight(.bold)
                .padding(.leading, 4)
                .fixedSize() // Prevents text from being cut off
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        
        // TUNED REACTIVITY (v2)
        // Lower noise gate to pick up subtle speech
        let power = CGFloat(max(0, controller.currentPower - 0.005)) 
        
        // Curve: 2.0 for a nice "pop" without being too jumpy
        let reactivePower = pow(power * 10, 2.0) 
        
        let multiplier: CGFloat = 25.0
        let idleMovement = sin(phase + Double(index) * 0.8) * 3
        
        // Centrality for 12 bars (center is between 5 and 6)
        let centrality = 1.0 - abs(CGFloat(index) - 5.5) / 6.0
        let voicedHeight = reactivePower * multiplier * centrality
        
        let finalHeight = base + voicedHeight + idleMovement
        
        return min(32, max(base, finalHeight))
    }
}

#Preview {
    ZStack {
        Color.gray.padding(100)
        RecordingOverlayView(controller: AppController())
    }
}
