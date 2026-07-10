cask "looped" do
  version "1.0.1"
  sha256 "0b6946ff894aac248961d7bb7388c39c642d9368d17fde503c51fad5d250fd62"

  url "https://github.com/rkkeepstrack/looped/releases/download/v#{version}/Looped-#{version}.zip"
  name "Looped"
  desc "Audio looper — waveform, A/B loop points, speed and pitch control"
  homepage "https://rkkeepstrack.github.io/looped/"

  depends_on macos: ">= :sequoia"

  app "Looped.app"

  caveats <<~EOS
    Looped is not notarized (no Apple Developer account), so macOS will
    refuse to open it until the quarantine flag is cleared:
      xattr -dr com.apple.quarantine "/Applications/Looped.app"
  EOS
end
