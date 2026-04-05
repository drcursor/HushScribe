cask "hushscribe" do
  version "2.6.5"
  sha256 "b59549cb0e285f63fd0fd22a8a426e80be5f7e64f758f7fcaf4a0cd896497949"

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
