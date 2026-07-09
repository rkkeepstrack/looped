//
//  TestDoubles.swift
//  loopedTests
//
//  Fakes + fixtures that let the view-model behavior (the automatable half of
//  TESTING.md) run in-process — no audio device, no file picker, no window server.
//  The app's protocol-backed, injected services are what make this possible.
//

import AVFoundation
@testable import looped

/// A spy `PlaybackService`: records what the view-model asked the "player" to do
/// and lets a test drive `isLooping` / the reported clock, without a real engine.
final class FakePlaybackService: PlaybackService {
	private(set) var setSourceCount = 0
	private(set) var playCount = 0
	private(set) var pauseCount = 0
	private(set) var stopCount = 0
	private(set) var seekCount = 0
	private(set) var lastSeek: TimeInterval?
	private(set) var scheduleLoopCount = 0
	private(set) var lastLoopStart: TimeInterval?
	private(set) var lastLoopLength: TimeInterval?
	private(set) var clearLoopCount = 0
	private(set) var lastRate: Float?
	private(set) var lastPitchCents: Float?
	private(set) var lastVarispeed: Float?
	private(set) var lastVolume: Float?

	var isLooping = false
	var fakeCurrentTime: TimeInterval = 0

	func setSource(file _: AVAudioFile, format _: AVAudioFormat) {
		setSourceCount += 1
	}

	func play() {
		playCount += 1
	}

	func pause() {
		pauseCount += 1
	}

	func stop() {
		stopCount += 1
	}

	func seek(to time: TimeInterval) {
		seekCount += 1
		lastSeek = time
		fakeCurrentTime = time
	}

	func scheduleLoop(_: AVAudioPCMBuffer, startTime: TimeInterval, length: TimeInterval) {
		scheduleLoopCount += 1
		lastLoopStart = startTime
		lastLoopLength = length
		isLooping = true
	}

	func clearLoop(resumeAt time: TimeInterval) {
		clearLoopCount += 1
		isLooping = false
		fakeCurrentTime = time
	}

	func currentTime() -> TimeInterval {
		fakeCurrentTime
	}

	func setRate(_ rate: Float) {
		lastRate = rate
	}

	func setPitch(_ cents: Float) {
		lastPitchCents = cents
	}

	func setVarispeed(_ rate: Float) {
		lastVarispeed = rate
	}

	func setVolume(_ volume: Float) {
		lastVolume = volume
	}
}

/// An `AudioFileService` that always rejects the load as too long — for exercising
/// the `PlayerViewModel.loadError` path without a real 20-minute file.
struct TooLongAudioFileService: AudioFileService {
	func load(url _: URL) async throws -> LoadedAudio {
		throw AudioFileServiceError.tooLong(maxMinutes: DefaultAudioFileService.maxDurationMinutes)
	}
}

/// Wraps the real decoder behind an artificial delay — lets a test overlap two
/// play requests deterministically (the double-click crash guard).
struct SlowAudioFileService: AudioFileService {
	let delay: Duration
	private let inner = DefaultAudioFileService()

	func load(url: URL) async throws -> LoadedAudio {
		try await Task.sleep(for: delay)
		return try await inner.load(url: url)
	}
}

enum FixtureError: Error { case setupFailed }

/// Writes a short quiet sine to a temp WAV and returns its URL. Used to produce a
/// real `LoadedAudio` (real file/buffer/format) for view-model + engine tests.
enum AudioFixture {
	static func tempSine(seconds: Double, sampleRate: Double = 8000) throws -> URL {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
			throw FixtureError.setupFailed
		}
		let frames = AVAudioFrameCount(seconds * sampleRate)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
		      let channel = buffer.floatChannelData
		else { throw FixtureError.setupFailed }
		buffer.frameLength = frames
		for i in 0 ..< Int(frames) {
			channel[0][i] = sinf(Float(i) * 0.05) * 0.3
		}

		// Unique name so concurrently-run tests (Swift Testing parallelizes by
		// default) never share or clobber the same fixture file.
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-fixture-\(UUID().uuidString).wav")
		let file = try AVAudioFile(forWriting: url, settings: format.settings)
		try file.write(from: buffer)
		return url
	}
}
