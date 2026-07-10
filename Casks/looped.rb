cask "looped" do
  version "1.0.0"
  sha256 "a847a14627fa84de48b23cacd0df0f6e010284389857c68b917127ed7897be98"

  url "https://github.com/rkkeepstrack/looped/releases/download/v#{version}/Looped-#{version}.zip"
  name "Looped"
  desc "Audio looper — waveform, A/B loop points, speed and pitch control"
  homepage "https://rkkeepstrack.github.io/looped/"

  depends_on macos: ">= :sequoia"

  app "Looped.app"

  caveats <<~EOS
    Looped is not notarized (no Apple Developer account). Install with:
      brew install --cask --no-quarantine looped
    or, if already installed and macOS refuses to open it:
      xattr -dr com.apple.quarantine /Applications/Looped.app
  EOS
end
