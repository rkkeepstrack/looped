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
bundle config="debug":
    #!/usr/bin/env python3
    import plistlib, shutil, subprocess, sys
    from pathlib import Path
    cfg = "{{config}}"
    # Build; keep swift's chatter on stderr so stdout is only the bundle path.
    subprocess.run(["swift", "build", "-c", cfg], check=True, stdout=sys.stderr)
    bin_dir = subprocess.run(
        ["swift", "build", "-c", cfg, "--show-bin-path"],
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
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "15.6",
        "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication",
    }
    with (app / "Contents/Info.plist").open("wb") as f:
        plistlib.dump(info, f)
    (app / "Contents/PkgInfo").write_text("APPL????")
    print(app)

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
