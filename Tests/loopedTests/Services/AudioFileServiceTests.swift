//
//  AudioFileServiceTests.swift
//  loopedTests
//
//  Tests the pure duration-limit logic and error messages of the file service,
//  plus one happy-path decode of a tiny WAV written to a temp file. The limit is
//  a pure function so the 20-minute boundary is checked without a huge fixture.
//

import AVFoundation
@testable import looped
import XCTest

@MainActor
final class AudioFileServiceTests: XCTestCase {
	// MARK: - Duration limit (pure)

	func testMaxDurationIsTwentyMinutes() {
		XCTAssertEqual(DefaultAudioFileService.maxDurationMinutes, 20)
	}

	func testExceedsDurationLimitBoundary() {
		let limit = Double(DefaultAudioFileService.maxDurationMinutes) * 60 // 1200 s
		XCTAssertFalse(DefaultAudioFileService.exceedsDurationLimit(0))
		XCTAssertFalse(DefaultAudioFileService.exceedsDurationLimit(limit - 0.1))
		XCTAssertFalse(DefaultAudioFileService.exceedsDurationLimit(limit)) // exactly 20 min is allowed
		XCTAssertTrue(DefaultAudioFileService.exceedsDurationLimit(limit + 0.001))
		XCTAssertTrue(DefaultAudioFileService.exceedsDurationLimit(limit * 2))
	}

	// MARK: - Error messages

	func testErrorDescriptions() {
		XCTAssertEqual(AudioFileServiceError.tooLong(maxMinutes: 20).errorDescription,
		               "That track is longer than 20 minutes.")
		XCTAssertEqual(AudioFileServiceError.bufferCreationFailed.errorDescription,
		               "Couldn't read that audio file.")
	}

	// MARK: - Happy-path decode

	func testLoadDecodesAShortFile() async throws {
		let url = try writeTempSine(seconds: 0.25, sampleRate: 8000)
		defer { try? FileManager.default.removeItem(at: url) }

		let loaded = try await DefaultAudioFileService().load(url: url)

		XCTAssertEqual(loaded.url, url)
		XCTAssertEqual(loaded.format.sampleRate, 8000, accuracy: 1e-6)
		XCTAssertEqual(loaded.duration, 0.25, accuracy: 0.02)
		XCTAssertGreaterThan(loaded.buffer.frameLength, 0)
	}

	// MARK: - Helpers

	/// Writes `seconds` of a quiet sine to a temp WAV and returns its URL.
	private func writeTempSine(seconds: Double, sampleRate: Double) throws -> URL {
		let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
		let frames = AVAudioFrameCount(seconds * sampleRate)
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
		buffer.frameLength = frames
		let channel = buffer.floatChannelData![0]
		for i in 0 ..< Int(frames) {
			channel[i] = sinf(Float(i) * 0.05) * 0.3
		}

		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-test-\(frames).wav")
		try? FileManager.default.removeItem(at: url)
		let file = try AVAudioFile(forWriting: url, settings: format.settings)
		try file.write(from: buffer)
		return url
	}
}
