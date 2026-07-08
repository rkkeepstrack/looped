# looped — command interface (Swift Package Manager).
# Run `just` (or `just --list`) to see recipes. Requires: swift, swiftformat, just.

set shell := ["bash", "-uc"]

# macOS: SwiftPM needs the full Xcode toolchain, not just the Command Line Tools.
export DEVELOPER_DIR := "/Applications/Xcode.app/Contents/Developer"

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

# Build a .app bundle and launch it as a proper GUI app.
run:
    open "$(scripts/make-app.sh debug)"

# Same, release build.
run-release:
    open "$(scripts/make-app.sh release)"

# Assemble the .app bundle without launching (prints its path).
bundle config="debug":
    @scripts/make-app.sh {{config}}

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
