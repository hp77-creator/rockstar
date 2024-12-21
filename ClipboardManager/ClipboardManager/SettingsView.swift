import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(UserDefaultsKeys.maxClipsShown) private var maxClipsShown: Int = 10
    @Environment(\.dismiss) var dismiss
    @State private var showFeedback = false
    
    var body: some View {
        VStack(spacing: 16) {
            Form {
                Section {
                    HStack {
                        Text("Number of clips to show:")
                            .foregroundColor(.primary)
                        Spacer()
                        TextField("", value: $maxClipsShown, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onChange(of: maxClipsShown) { newValue in
                                // Ensure value stays within bounds
                                if newValue < 5 {
                                    maxClipsShown = 5
                                } else if newValue > 50 {
                                    maxClipsShown = 50
                                }
                                
                                withAnimation {
                                    showFeedback = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        showFeedback = false
                                    }
                                }
                            }
                        
                        // Keep the stepper for incremental adjustments
                        Stepper("", value: $maxClipsShown, in: 5...50, step: 5)
                            .labelsHidden()
                    }
                    
                    Text("Min: 5, Max: 50")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Display")
                        .font(.headline)
                }
            }
            .formStyle(.grouped)
            
            if showFeedback {
                Text("Setting saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.vertical)
        .frame(width: 350)
        .fixedSize()
    }
}

#Preview {
    SettingsView()
}
