cask "rockstar" do
  version "0.1.1" # Update this version to match your release version
  sha256 "REPLACE_WITH_ACTUAL_SHA256" # You'll need to update this after creating the DMG

  url "https://github.com/hp77-creator/rockstar/releases/download/v#{version}/Rockstar.dmg"
  name "Rockstar"
  desc "A powerful clipboard manager for macOS with Obsidian sync capabilities"
  homepage "https://github.com/hp77-creator/rockstar"

  depends_on macos: ">= :ventura" # Based on LSMinimumSystemVersion in Info.plist (13.0)

  app "Rockstar.app"

  zap trash: [
    "~/Library/Application Support/Rockstar",
    "~/Library/Preferences/com.hp77.ClipboardManager.plist",
    "~/Library/Caches/Rockstar",
    "~/Library/Logs/Rockstar"
  ]
end
