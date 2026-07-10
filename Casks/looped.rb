cask "looped" do
  version "1.0.0"
  sha256 "de50e285ba409e8696354c3d93daaac03ae57679b47fc24613d5aa1d3954ad8b"

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
