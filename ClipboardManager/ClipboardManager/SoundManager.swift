import AppKit
import Foundation

// Debug print to verify sound settings
public class SoundManager {
    public static let shared = SoundManager()
    private var sound: NSSound?
    
    private init() {
        // Try to load the Tink sound
        if let tinkSound = NSSound(named: "Tink") {
            print("Successfully loaded Tink sound")
            tinkSound.volume = 0.3  // Moderate volume for clear feedback
            sound = tinkSound
        } else {
            print("Failed to load Tink sound, will use default")
        }
    }
    
    public func playCopySound() {
        let shouldPlaySound = UserDefaults.standard.bool(forKey: UserDefaultsKeys.playSoundOnCopy)
        print("Should play sound: \(shouldPlaySound)")
        if shouldPlaySound {
            if let existingSound = sound {
                print("Playing Tink sound")
                existingSound.play()
            } else {
                print("Playing fallback sound")
                NSSound.beep()
            }
        }
    }
}
