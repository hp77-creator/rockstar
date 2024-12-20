#!/bin/bash
set -e

# Build Go binary
echo "Building Go binary..."
PROJECT_ROOT=$(pwd)
cd "$PROJECT_ROOT"
echo "Building from $PROJECT_ROOT"
go build -o "$PROJECT_ROOT/macos/ClipboardManager/clipboard-manager" "$PROJECT_ROOT/cmd/clipboard-manager/main.go"

# Create project structure
echo "Creating project structure..."
cd macos/ClipboardManager
mkdir -p ClipboardManager/Sources
mkdir -p ClipboardManager/Resources
mkdir -p ClipboardManager.xcodeproj

# Copy Swift files
cp ClipboardManagerApp.swift ClipboardManager/Sources/
cp Models.swift ClipboardManager/Sources/
cp APIClient.swift ClipboardManager/Sources/
cp ClipboardHistoryView.swift ClipboardManager/Sources/

# Copy Go binary and Info.plist
cp clipboard-manager ClipboardManager/Resources/
cp Info.plist ClipboardManager/Resources/

# Create project.pbxproj
cat > ClipboardManager.xcodeproj/project.pbxproj << EOL
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 55;
    objects = {
        /* Begin PBXBuildFile section */
        // Add your source files here
        /* End PBXBuildFile section */
    };
    rootObject = 1234567890ABCDEF /* Project object */;
}
EOL

echo "Setup complete!"
echo "Next steps:"
echo "1. Open Xcode"
echo "2. File > New > Project"
echo "3. Choose macOS > App"
echo "4. Name it ClipboardManager"
echo "5. Replace the generated files with the ones in ClipboardManager/Sources"
echo "6. Add the Resources to your project"
echo "1. Select the project in the navigator"
echo "2. Select the ClipboardManager target"
echo "3. Select the Signing & Capabilities tab"
echo "4. Choose your development team"
echo "5. Set a unique bundle identifier"
