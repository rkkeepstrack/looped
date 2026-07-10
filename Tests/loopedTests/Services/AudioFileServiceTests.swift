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
import Testing

struct AudioFileServiceTests {
	// MARK: - Duration limit (pure)

	@Test func maxDurationIsTwentyMinutes() {
		#expect(DefaultAudioFileService.maxDurationMinutes == 20)
	}

	@Test func exceedsDurationLimitBoundary() {
		let limit = Double(DefaultAudioFileService.maxDurationMinutes) * 60 // 1200 s
		#expect(!DefaultAudioFileService.exceedsDurationLimit(0))
		#expect(!DefaultAudioFileService.exceedsDurationLimit(limit - 0.1))
		#expect(!DefaultAudioFileService.exceedsDurationLimit(limit)) // exactly 20 min is allowed
		#expect(DefaultAudioFileService.exceedsDurationLimit(limit + 0.001))
		#expect(DefaultAudioFileService.exceedsDurationLimit(limit * 2))
	}

	// MARK: - Error messages

	@Test func errorDescriptionsNameTheFile() {
		#expect(
			AudioFileServiceError.tooLong(filename: "song.wav", maxMinutes: 20).errorDescription
				== "“song.wav” is longer than 20 minutes."
		)
		#expect(
			AudioFileServiceError.bufferCreationFailed(filename: "song.wav").errorDescription
				== "Couldn't read “song.wav”."
		)
	}

	// MARK: - Happy-path decode

	@Test func loadDecodesAShortFile() async throws {
		let url = try writeTempSine(seconds: 0.25, sampleRate: 8000)
		defer { try? FileManager.default.removeItem(at: url) }

		let loaded = try await DefaultAudioFileService().load(url: url)

		#expect(loaded.url == url)
		#expect(loaded.format.sampleRate == 8000)
		#expect(abs(loaded.duration - 0.25) <= 0.02)
		#expect(loaded.buffer.frameLength > 0)
	}

	// MARK: - Helpers

	/// Writes `seconds` of a quiet sine to a unique temp WAV and returns its URL.
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
			.appendingPathComponent("looped-test-\(UUID().uuidString).wav")
		let file = try AVAudioFile(forWriting: url, settings: format.settings)
		try file.write(from: buffer)
		return url
	}
}
