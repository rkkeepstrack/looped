# looped

A macOS SwiftUI audio-looping app: load a track (WAV/MP3/AIFF), scrub an interactive
waveform, set A/B loop points, and play back with adjustable speed and volume.

## Prerequisites

- **macOS 15+** with the **Command Line Tools** (`xcode-select --install`). That's the only
  toolchain needed — build, run, *and* test all work without full Xcode (tests use Swift
  Testing, not XCTest). Full Xcode works too if you have it.
- [Homebrew](https://brew.sh), then install the dev tools:

  ```bash
  brew bundle          # installs just + swiftformat (see Brewfile)
  ```

## Run

```bash
just run               # build a .app bundle and launch it
```

## Develop

```bash
just                   # list all recipes
just build             # build (debug)
just test              # run the unit tests — headless, no Xcode
just format            # reformat with SwiftFormat
```

Sources are in `Sources/looped/`, tests in `Tests/loopedTests/`. See **`CLAUDE.md`** for the
architecture and **`TESTING.md`** for the manual QA checklist.
