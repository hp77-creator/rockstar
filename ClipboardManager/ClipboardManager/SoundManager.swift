import AppKit
import Foundation

// Available system sounds
public enum SystemSound: String, CaseIterable {
    case tink = "Tink"
    case pop = "Pop"
    case glass = "Glass"
    case hero = "Hero"
    case purr = "Purr"
    
    public var displayName: String {
        switch self {
        case .tink: return "Tink (Light)"
        case .pop: return "Pop (Soft)"
        case .glass: return "Glass (Clear)"
        case .hero: return "Hero (Bold)"
        case .purr: return "Purr (Gentle)"
        }
    }
}

// Debug print to verify sound settings
public class SoundManager {
    public static let shared = SoundManager()
    private var sounds: [SystemSound: NSSound] = [:]
    
    private init() {
        // Try to load all system sounds
        for soundType in SystemSound.allCases {
            if let sound = NSSound(named: soundType.rawValue) {
                print("Successfully loaded \(soundType.rawValue) sound")
                sound.volume = 0.3  // Moderate volume for clear feedback
                sounds[soundType] = sound
            } else {
                print("Failed to load \(soundType.rawValue) sound")
            }
        }
    }
    
    public func playCopySound() {
        let shouldPlaySound = UserDefaults.standard.bool(forKey: UserDefaultsKeys.playSoundOnCopy)
        print("Should play sound: \(shouldPlaySound)")
        if shouldPlaySound {
            let selectedSound = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedSound) ?? SystemSound.tink.rawValue
            if let soundType = SystemSound(rawValue: selectedSound),
               let sound = sounds[soundType] {
                print("Playing \(soundType.rawValue) sound")
                sound.play()
            } else {
                print("Playing fallback sound")
                NSSound.beep()
            }
        }
    }
}
