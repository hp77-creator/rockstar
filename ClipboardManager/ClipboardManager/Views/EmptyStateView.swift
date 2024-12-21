import SwiftUI

struct EmptyStateView: View {
    let isServiceRunning: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            if isServiceRunning {
                Image(systemName: "clipboard")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No clips available")
                    .foregroundColor(.secondary)
                Text("Copy something to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Waiting for service to start...")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 300, height: 400)
    }
}

struct EmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EmptyStateView(isServiceRunning: true)
                .previewDisplayName("Service Running")
            
            EmptyStateView(isServiceRunning: false)
                .previewDisplayName("Service Stopped")
        }
    }
}
