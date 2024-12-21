import SwiftUI

struct DeleteConfirmationView: View {
    let clipToDelete: ClipboardItem
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Delete Clip")
                .font(.headline)
            
            Text("Are you sure you want to delete this clip?")
                .font(.body)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Delete") {
                    onDelete()
                }
                .keyboardShortcut(.defaultAction)
                .foregroundColor(.red)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 300)
    }
}
