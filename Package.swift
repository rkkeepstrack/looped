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
			dependencies: ["looped"],
			path: "Tests/loopedTests"
		),
	],
	// The sources predate Swift 6 strict concurrency (they were built in language
	// mode 5 with default main-actor isolation). Pin mode 5 so that behaviour — and
	// the code — carries over unchanged.
	swiftLanguageModes: [.v5]
)
