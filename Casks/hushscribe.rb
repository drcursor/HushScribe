cask "hushscribe" do
  version "2.4.1"
  sha256 "a119648cbb38cf42e6d283259e2ff905944bb7a08b173d104d4e7a5cdff31491"

  url "https://github.com/drcursor/HushScribe/releases/download/v#{version}/HushScribe.dmg"
  name "HushScribe"
  desc "Local meeting transcription and capture for Obsidian vaults"
  homepage "https://github.com/drcursor/HushScribe"

  depends_on macos: ">= :sequoia"

  caveats "You must run xattr -d com.apple.quarantine /Applications/HushScribe.app so that macOS Gatekeeper unblocks the application from running."

  app "HushScribe.app"

  zap trash: [
    "~/Library/Application Support/HushScribe",
    "~/Library/Preferences/com.drcursor.hushscribe.plist",
    "~/Documents/HushScribe",
  ]
end
