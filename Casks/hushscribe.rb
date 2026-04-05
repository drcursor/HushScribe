cask "hushscribe" do
  version "2.6.0"
  sha256 "86d2a97980e709515591cd02cca91d6f7082ff13f0688e9dae6d16ea7599d340"

  url "https://github.com/drcursor/HushScribe/releases/download/v#{version}/HushScribe.dmg"
  name "HushScribe"
  desc "Local meeting transcription and capture for Obsidian vaults"
  homepage "https://github.com/drcursor/HushScribe"

  depends_on macos: ">= :sequoia"

  caveats "You must run xattr -d com.apple.quarantine /Applications/HushScribe.app so that macOS Gatekeeper unblocks the application."

  app "HushScribe.app"

  zap trash: [
    "~/Library/Application Support/HushScribe",
    "~/Library/Preferences/com.drcursor.hushscribe.plist",
    "~/Documents/HushScribe",
  ]
end
