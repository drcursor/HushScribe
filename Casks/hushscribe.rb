cask "hushscribe" do
  version "3.4.0"
  sha256 "2449d7d5bc6db6c8dcdae5a36df89daec83c1961b2fd9fb7547e20845fd20a70"

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
