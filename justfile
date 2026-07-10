# looped — command interface (Swift Package Manager).
# Run `just` (or `just --list`) to see recipes. Requires: swift, swiftformat, just.

set shell := ["bash", "-uc"]

# Uses whatever toolchain `xcode-select` points at — the Command Line Tools are
# enough for build/run/test (tests use Swift Testing, not XCTest, so no full Xcode).

# Show the recipe list (default).
default:
    @just --list

# Build the app (debug).
build:
    swift build

# Build the app (release).
build-release:
    swift build -c release

# Run the unit tests — headless, no Xcode. Pass extra args, e.g. `just test --filter Looping`.
test *ARGS:
    swift test {{ARGS}}

# Build a .app bundle and launch it as a proper GUI app (`just run release` for release).
run config="debug":
    open "$(just bundle {{config}})"

# A bare `swift run` starts the binary unbundled (no Dock/menu/focus), so we wrap it
# in a minimal .app. Build output goes to stderr; only the bundle path hits stdout.
# Assemble .build/Looped.app around the built binary and print its path (no launch).
# `universal=1` builds arm64 + x86_64 (release distribution); default is host-only.
bundle config="debug" version="1.0.0" universal="":
    #!/usr/bin/env python3
    import plistlib, shutil, subprocess, sys
    from pathlib import Path
    cfg = "{{config}}"
    arch = ["--arch", "arm64", "--arch", "x86_64"] if "{{universal}}" else []
    # Build; keep swift's chatter on stderr so stdout is only the bundle path.
    subprocess.run(["swift", "build", "-c", cfg, *arch], check=True, stdout=sys.stderr)
    bin_dir = subprocess.run(
        ["swift", "build", "-c", cfg, *arch, "--show-bin-path"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    app = Path(".build/Looped.app")
    macos = app / "Contents/MacOS"
    shutil.rmtree(app, ignore_errors=True)
    macos.mkdir(parents=True)
    shutil.copy(Path(bin_dir) / "looped", macos / "looped")
    icns = Path("assets/AppIcon.icns")
    if icns.exists():
        resources = app / "Contents/Resources"
        resources.mkdir()
        shutil.copy(icns, resources / "AppIcon.icns")
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": "looped",
        "CFBundleIconFile": "AppIcon",
        "CFBundleIdentifier": "RK.looped",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Looped",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "{{version}}",
        "CFBundleVersion": "{{version}}",
        "LSMinimumSystemVersion": "15.6",
        "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication",
    }
    with (app / "Contents/Info.plist").open("wb") as f:
        plistlib.dump(info, f)
    (app / "Contents/PkgInfo").write_text("APPL????")
    print(app)

# Release a new version end-to-end: verify a clean, pushed main, then tag
# v<version> and push the tag — the release.yml pipeline does the rest
# (tests, universal zip, GitHub release, cask bump on main).
ship version:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "$(git branch --show-current)" == "main" ]] || { echo "not on main" >&2; exit 1; }
    git diff-index --quiet HEAD || { echo "working tree not clean" >&2; exit 1; }
    git push origin main
    git tag "v{{version}}"
    git push origin "v{{version}}"
    echo "tagged v{{version}} — release pipeline running: https://github.com/rkkeepstrack/looped/actions"

# Build a universal release zip for GitHub Releases and print its sha256
# (paste into Casks/looped.rb). Output: .build/Looped-<version>.zip
release version="1.0.0":
    #!/usr/bin/env bash
    set -euo pipefail
    app=$(just bundle release {{version}} 1)
    zip=".build/Looped-{{version}}.zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    echo "$zip"
    shasum -a 256 "$zip"

# Regenerate assets/AppIcon.icns from assets/AppIcon.svg (needs librsvg; iconutil
# ships with macOS). The .icns is checked in, so this only runs after icon edits.
icon:
    #!/usr/bin/env bash
    set -euo pipefail
    iconset=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        rsvg-convert -w "$size" -h "$size" assets/AppIcon.svg -o "$iconset/icon_${size}x${size}.png"
        rsvg-convert -w "$((size * 2))" -h "$((size * 2))" assets/AppIcon.svg -o "$iconset/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$iconset" -o assets/AppIcon.icns
    echo "wrote assets/AppIcon.icns"

# Reformat all Swift sources (SwiftFormat, config: .swiftformat).
format:
    swiftformat .

# Check formatting without writing changes (use in CI / pre-commit).
format-check:
    swiftformat --lint .

# Resolve/update package dependencies.
resolve:
    swift package resolve

# Remove build artifacts.
clean:
    swift package clean
    rm -rf .build/Looped.app
