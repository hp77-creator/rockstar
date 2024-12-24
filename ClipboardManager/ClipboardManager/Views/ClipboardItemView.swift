import SwiftUI

struct ClipboardItemView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onDelete: () -> Void
    let onPaste: () async throws -> Void
    
    @State private var isHovered = false
    @State private var isPasting = false
    @State private var isDeleting = false
    @State private var error: Error?
    
    var body: some View {
        HStack(spacing: 8) {
            // Main content with paste action
            VStack(alignment: .leading, spacing: 4) {
                ClipboardItemContentView(
                    type: item.type,
                    content: item.content,
                    contentString: item.contentString
                )
                .lineLimit(2)
                
                // Metadata
                HStack {
                    if let sourceApp = item.metadata.sourceApp {
                        HStack(spacing: 4) {
                            Image(systemName: "app.badge")
                                .foregroundColor(.secondary)
                            Text(sourceApp)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isPasting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(item.createdAt, style: .relative)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    isPasting = true
                    do {
                        try await onPaste()
                    } catch {
                        print("Failed to paste clip: \(error)")
                        self.error = error
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    isPasting = false
                }
            }
            
            // Delete button area
            if isHovered && !isPasting {
                Button(action: {
                    guard !isDeleting else { return }
                    DeleteConfirmationWindowController.showDeleteConfirmation(
                        for: item,
                        onDelete: {
                            isDeleting = true
                            onDelete()
                        }
                    )
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                        .opacity(isDeleting ? 0.7 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32)
                .padding(.trailing, 4)
                .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 32)
                    .padding(.trailing, 4)
            }
        }
        .padding(.vertical, 4)
        .background(
            Group {
                if isSelected {
                    Color.blue.opacity(0.2)
                } else if isHovered {
                    Color.gray.opacity(0.1)
                } else {
                    Color.clear
                }
            }
        )
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") {
                error = nil
            }
        } message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        }
    }
}
