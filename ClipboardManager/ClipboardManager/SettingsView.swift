import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(UserDefaultsKeys.maxClipsShown) private var maxClipsShown: Int = 10
    @AppStorage(UserDefaultsKeys.obsidianEnabled) private var obsidianEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.obsidianVaultPath) private var obsidianVaultPath: String = ""
    @AppStorage(UserDefaultsKeys.obsidianVaultBookmark) private var obsidianVaultBookmark: Data?
    @AppStorage(UserDefaultsKeys.obsidianSyncInterval) private var obsidianSyncInterval: Int = 5
    @AppStorage(UserDefaultsKeys.playSoundOnCopy) private var playSoundOnCopy: Bool = false
    @AppStorage(UserDefaultsKeys.selectedSound) private var selectedSound: String = SystemSound.tink.rawValue
    
    @Environment(\.dismiss) var dismiss
    @State private var showFeedback = false
    
    var body: some View {
        VStack(spacing: 16) {
            Form {
                // Sound Settings
                Section {
                    Toggle("Play sound on copy", isOn: $playSoundOnCopy)
                        .help("Play a notification sound when text is copied")
                        .onChange(of: playSoundOnCopy) { oldValue, newValue in
                            print("Sound setting changed to: \(newValue)")
                            withAnimation {
                                showFeedback = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showFeedback = false
                                }
                            }
                            // Play test sound when enabled
                            if newValue {
                                print("Playing test sound")
                                SoundManager.shared.playCopySound()
                            }
                        }
                    
                    if playSoundOnCopy {
                        Picker("Sound", selection: $selectedSound) {
                            ForEach(SystemSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound.rawValue)
                            }
                        }
                        .onChange(of: selectedSound) { oldValue, newValue in
                            withAnimation {
                                showFeedback = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showFeedback = false
                                }
                            }
                            // Play test sound when changed
                            SoundManager.shared.playCopySound()
                        }
                    }
                } header: {
                    Text("Sound")
                }
                
                // Display Settings
                Section {
                    HStack {
                        Text("Number of clips to show:")
                            .foregroundColor(.primary)
                        Spacer()
                        TextField("", value: $maxClipsShown, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onChange(of: maxClipsShown) { oldValue, newValue in
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
                }
                
                // Obsidian Integration Settings
                Section {
                    Toggle("Enable Obsidian Integration", isOn: $obsidianEnabled)
                    
                    if obsidianEnabled {
                        Button(obsidianVaultPath.isEmpty ? "Select Vault Path" : "Change Vault Path") {
                            selectObsidianVaultPath()
                        }
                        
                        if !obsidianVaultPath.isEmpty {
                            Text(obsidianVaultPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Picker("Sync Interval", selection: $obsidianSyncInterval) {
                            Text("1 minute").tag(1)
                            Text("5 minutes").tag(5)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                        }
                    }
                } header: {
                    Text("Obsidian Integration")
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
                            .onChange(of: obsidianEnabled) { oldValue, newValue in
            withAnimation {
                showFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showFeedback = false
                }
            }
            // Restart Go service to apply Obsidian settings
            NotificationCenter.default.post(name: NSNotification.Name("RestartGoService"), object: nil)
        }
                            .onChange(of: obsidianVaultPath) { oldValue, newValue in
            withAnimation {
                showFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showFeedback = false
                }
            }
            // Restart Go service to apply Obsidian settings
            NotificationCenter.default.post(name: NSNotification.Name("RestartGoService"), object: nil)
        }
                            .onChange(of: obsidianSyncInterval) { oldValue, newValue in
            withAnimation {
                showFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showFeedback = false
                }
            }
            // Restart Go service to apply Obsidian settings
            NotificationCenter.default.post(name: NSNotification.Name("RestartGoService"), object: nil)
        }
        .padding(.vertical)
        .frame(width: 350)
        .fixedSize()
    }
    
    private func selectObsidianVaultPath() {
        let panel = NSOpenPanel()
        panel.title = "Select Obsidian Vault"
        panel.showsResizeIndicator = true
        panel.showsHiddenFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                // Create security-scoped bookmark
                if let bookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    // Store bookmark and path
                    obsidianVaultBookmark = bookmark
                    obsidianVaultPath = url.path
                    
                    withAnimation {
                        showFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showFeedback = false
                        }
                    }
                } else {
                    print("Failed to create security-scoped bookmark")
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
