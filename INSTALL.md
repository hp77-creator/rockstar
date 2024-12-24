# Installation Guide

## For Users

### Installing from DMG
1. Download the ClipboardManager DMG file
2. Double-click the DMG file to mount it
3. Drag the ClipboardManager app to your Applications folder
4. Since the app isn't signed with an Apple Developer ID, you'll need to:
   - Right-click the app and select "Open" the first time
   - Click "Open" in the security dialog that appears
   - Or go to System Preferences > Security & Privacy and click "Open Anyway"

## For Developers

### Creating a Release

1. Archive the app in Xcode:
   - Select Product > Archive
   - Once archived, copy the app to the releases folder with appropriate version

2. Create DMG for distribution:
   ```bash
   # Install create-dmg if not already installed
   brew install create-dmg

   # Create DMG file
   create-dmg \
     --volname "ClipboardManager" \
     --window-pos 200 120 \
     --window-size 800 400 \
     --icon-size 100 \
     --icon "ClipboardManager.app" 200 190 \
     --app-drop-link 600 185 \
     "ClipboardManager-[VERSION].dmg" \
     "releases/ClipboardManager.v.[VERSION]/ClipboardManager.app"
   ```
   Replace [VERSION] with the actual version number (e.g., 1.2)

### Notes
- The DMG creation process will automatically:
  - Create a window with custom positioning
  - Add an Applications folder shortcut for easy installation
  - Set appropriate icon sizes and positions
  - Compress the final DMG file

### Future Improvements
- Code signing with Apple Developer ID
- Notarization for improved security
- Automatic update mechanism
