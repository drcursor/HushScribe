cask "hushscribe" do
  version "3.3.0"
  sha256 "b3773c68fc520f0319d710291a8b27ac26d29421bf66c7e5e882efbb96d99c5e"

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
