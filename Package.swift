// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "looped",
	platforms: [
		.macOS(.v15),
	],
	products: [
		.executable(name: "looped", targets: ["looped"]),
	],
	dependencies: [
		.package(url: "https://github.com/dmrschmidt/DSWaveformImage", from: "14.2.2"),
		// Swift Testing as a *source* dependency so `swift test` needs no XCTest — and
		// therefore no full Xcode (the Command Line Tools ship neither XCTest nor the
		// toolchain's bundled Testing). Pinned to match the CLT's Swift 6.1 toolchain:
		// 6.2+ tags declare a tools-version newer than 6.1 can parse. Bump when the CLT
		// advances.
		.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.1.3"),
	],
	targets: [
		.executableTarget(
			name: "looped",
			dependencies: [
				.product(name: "DSWaveformImage", package: "DSWaveformImage"),
				.product(name: "DSWaveformImageViews", package: "DSWaveformImage"),
			],
			path: "Sources/looped",
			// Asset catalog is system-only (AppIcon/AccentColor) and unreferenced in
			// code; the .app bundle wires it up (see justfile), so keep it out of the
			// SwiftPM build to avoid an unhandled-resource warning.
			exclude: ["Assets.xcassets"]
		),
		.testTarget(
			name: "loopedTests",
			dependencies: [
				"looped",
				.product(name: "Testing", package: "swift-testing"),
			],
			path: "Tests/loopedTests"
		),
	],
	// The sources predate Swift 6 strict concurrency (they were built in language
	// mode 5 with default main-actor isolation). Pin mode 5 so that behaviour — and
	// the code — carries over unchanged.
	swiftLanguageModes: [.v5]
)
