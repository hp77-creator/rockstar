import SwiftUI

struct ToastView: View {
    let message: String
    
    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.75))
                .cornerRadius(10)
                .padding(.bottom)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        ToastView(message: "Content copied! Press Cmd+V to paste")
    }
}
