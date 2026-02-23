cask "burn" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/maferland/burn/releases/download/v#{version}/Burn-v#{version}-macos.dmg"
  name "Burn"
  desc "Track Claude Code spending from the macOS menu bar"
  homepage "https://github.com/maferland/burn"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Burn.app"

  zap trash: [
    "~/Library/Preferences/com.maferland.burn.plist",
  ]
end
