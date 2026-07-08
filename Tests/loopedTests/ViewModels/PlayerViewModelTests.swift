//
//  PlayerViewModelTests.swift
//  loopedTests
//
//  Automates the transport / looping / loading rows of TESTING.md at the view-model
//  layer: a spy PlaybackService records the intents, a real decode gives a genuine
//  LoadedAudio, and a real LoopingService produces the loop buffer. What stays
//  manual (audio quality, timer-driven clock, visuals) is noted in TESTING.md.
//

import AVFoundation
@testable import looped
import XCTest

@MainActor
final class PlayerViewModelTests: XCTestCase {
	private var fake: FakePlaybackService!
	private var fixture: URL!

	override func setUp() async throws {
		try await super.setUp()
		fake = FakePlaybackService()
		fixture = try AudioFixture.tempSine(seconds: 1)
	}

	override func tearDown() async throws {
		if let fixture { try? FileManager.default.removeItem(at: fixture) }
		fake = nil
		fixture = nil
		try await super.tearDown()
	}

	/// A view-model with the spy player and a really-decoded 1 s track loaded.
	private func loadedViewModel() async -> PlayerViewModel {
		let vm = PlayerViewModel(playback: fake, files: DefaultAudioFileService(), looping: DefaultLoopingService())
		await vm.load(url: fixture)
		return vm
	}

	// MARK: - Loading

	func testLoadPopulatesStateAndPointsThePlayerAtTheFile() async {
		let vm = await loadedViewModel()

		XCTAssertNil(vm.loadError)
		XCTAssertEqual(vm.currentFileName, fixture.lastPathComponent)
		XCTAssertEqual(vm.audioURL, fixture)
		XCTAssertEqual(vm.duration ?? 0, 1.0, accuracy: 0.05)
		XCTAssertEqual(fake.setSourceCount, 1)
		XCTAssertFalse(vm.isPlaying)
	}

	func testLoadingTooLongFileSurfacesAnError() async {
		let vm = PlayerViewModel(playback: fake, files: TooLongAudioFileService(), looping: DefaultLoopingService())
		await vm.load(url: fixture)

		XCTAssertEqual(vm.loadError, "That track is longer than 20 minutes.")
		XCTAssertNil(vm.currentFileName) // nothing loaded
		XCTAssertEqual(fake.setSourceCount, 0)
	}

	func testReloadResetsLoopPointsAndTime() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.1)
		vm.setLoopEnd(time: 0.5)
		vm.currentTime = 0.4

		let second = try? AudioFixture.tempSine(seconds: 1, sampleRate: 16000)
		defer { if let second { try? FileManager.default.removeItem(at: second) } }
		await vm.load(url: second ?? fixture)

		XCTAssertNil(vm.loopStart.0)
		XCTAssertNil(vm.loopEnd.0)
		XCTAssertEqual(vm.currentTime, 0)
	}

	// MARK: - Transport

	func testTogglePlayPause() async {
		let vm = await loadedViewModel()

		vm.togglePlayPause()
		XCTAssertTrue(vm.isPlaying)
		XCTAssertEqual(fake.playCount, 1)

		vm.togglePlayPause()
		XCTAssertFalse(vm.isPlaying)
		XCTAssertEqual(fake.pauseCount, 1)
	}

	func testTogglePlayPauseDoesNothingWithoutALoadedFile() {
		let vm = PlayerViewModel(playback: fake, files: DefaultAudioFileService(), looping: DefaultLoopingService())
		vm.togglePlayPause()
		XCTAssertFalse(vm.isPlaying)
		XCTAssertEqual(fake.playCount, 0)
	}

	func testStopResetsToStart() async {
		let vm = await loadedViewModel()
		vm.togglePlayPause()
		vm.currentTime = 0.6

		vm.stop()
		XCTAssertFalse(vm.isPlaying)
		XCTAssertEqual(vm.currentTime, 0)
		XCTAssertEqual(fake.stopCount, 1)
	}

	// MARK: - Seeking (jumpTo)

	func testJumpToSeeksWhenInBounds() async {
		let vm = await loadedViewModel()
		XCTAssertTrue(vm.jumpTo(time: 0.5))
		XCTAssertEqual(fake.lastSeek ?? -1, 0.5, accuracy: 1e-9)
		XCTAssertEqual(vm.currentTime, 0.5, accuracy: 1e-9)
	}

	func testJumpToIgnoresOutOfBounds() async {
		let vm = await loadedViewModel()
		XCTAssertFalse(vm.jumpTo(time: 99)) // past the end
		XCTAssertFalse(vm.jumpTo(time: -1)) // before the start
		XCTAssertEqual(fake.seekCount, 0)
	}

	func testJumpToStaysInLoopWhileArmed() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.1)
		vm.setLoopEnd(time: 0.5)
		XCTAssertTrue(fake.isLooping)

		// Scrubbing while looping must be a no-op seek (stays in the loop).
		XCTAssertFalse(vm.jumpTo(time: 0.3))
		XCTAssertEqual(fake.seekCount, 0)
	}

	// MARK: - Looping

	func testValidRangeArmsTheLoop() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)

		XCTAssertTrue(fake.isLooping)
		XCTAssertEqual(fake.scheduleLoopCount, 1)
		XCTAssertEqual(fake.lastLoopStart ?? -1, 0.2, accuracy: 1e-9)
		XCTAssertEqual(fake.lastLoopLength ?? -1, 0.6, accuracy: 1e-9)
		XCTAssertEqual(vm.currentTime, 0.2, accuracy: 1e-9) // jumps to A
	}

	func testInvertedRangeDoesNotArm() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.8)
		vm.setLoopEnd(time: 0.2) // B < A
		XCTAssertFalse(fake.isLooping)
		XCTAssertEqual(fake.scheduleLoopCount, 0)
	}

	func testClearingAPointDisarmsTheLoop() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)
		XCTAssertTrue(fake.isLooping)

		vm.setLoopStart(time: nil)
		XCTAssertFalse(fake.isLooping)
		XCTAssertEqual(fake.clearLoopCount, 1)
	}

	// MARK: - Parameters

	func testRateAndVolumeReachThePlayer() async {
		let vm = await loadedViewModel()
		vm.rate = 1.5
		vm.updateRate()
		vm.updateVolume(volume: 0.25)

		XCTAssertEqual(fake.lastRate ?? -1, 1.5, accuracy: 1e-6)
		XCTAssertEqual(fake.lastVolume ?? -1, 0.25, accuracy: 1e-6)
	}

	// MARK: - Derived

	func testProgressInPercent() async {
		let vm = await loadedViewModel()
		vm.currentTime = 0.25
		XCTAssertEqual(vm.getProgressInPercent(), 0.25, accuracy: 0.02)
	}
}
