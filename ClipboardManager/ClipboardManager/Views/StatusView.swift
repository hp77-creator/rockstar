import SwiftUI

struct StatusView: View {
    let isServiceRunning: Bool
    let error: String?
    
    var body: some View {
        VStack(spacing: 4) {
            // Status indicator
            HStack {
                Circle()
                    .fill(isServiceRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isServiceRunning ? "Service Running" : "Service Stopped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StatusView(
                isServiceRunning: true,
                error: nil
            )
            
            StatusView(
                isServiceRunning: false,
                error: "Failed to connect"
            )
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
