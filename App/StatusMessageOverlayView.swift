import SwiftUI

struct StatusMessageOverlayView: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minWidth: 160, maxWidth: 240, minHeight: 56)
        .background {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
    }
}

#Preview {
    StatusMessageOverlayView(
        iconName: "xmark.octagon.fill",
        iconColor: .red,
        title: "Error: input too short",
        subtitle: "Try speaking a bit longer."
    )
    .padding()
    .background(Color.black.opacity(0.6))
}
