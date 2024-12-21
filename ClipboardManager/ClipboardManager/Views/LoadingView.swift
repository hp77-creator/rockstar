import SwiftUI

struct LoadingView: View {
    let message: String
    
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 300, height: 400)
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LoadingView(message: "Loading clips...")
                .previewDisplayName("Loading")
            
            LoadingView(message: "Searching...")
                .previewDisplayName("Searching")
        }
    }
}
