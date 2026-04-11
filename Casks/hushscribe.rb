cask "hushscribe" do
  version "3.1.0"
  sha256 "17b9f196125de1acfe40e2c5c1708bd3ad52b9795e6daa60a98fb9b19c703f65"

  url "https://github.com/drcursor/HushScribe/releases/download/v#{version}/HushScribe.dmg"
  name "HushScribe"
  desc "Local meeting transcription and capture for Obsidian vaults"
  homepage "https://github.com/drcursor/HushScribe"

  depends_on macos: ">= :sequoia"

  app "HushScribe.app"

  zap trash: [
    "~/Library/Application Support/HushScribe",
    "~/Library/Preferences/com.drcursor.hushscribe.plist",
    "~/Documents/HushScribe",
  ]
end
