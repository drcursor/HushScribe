cask "hushscribe" do
  version "2.4.1"
  sha256 "bc7b5b84a70360cb40c17f16780fd7d12c9fc178d076d969589afb884a424517"

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
