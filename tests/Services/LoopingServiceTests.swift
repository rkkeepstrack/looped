//
//  LoopingServiceTests.swift
//  loopedTests
//
//  Unit tests for `DefaultLoopingService.makeLoopBuffer` — the pure loop-slice +
//  crossfade DSP. Source buffers are filled with a ramp (sample[i] == Float(i))
//  so every asserted sample maps back to a known source frame.
//

import AVFoundation
@testable import looped
import XCTest

@MainActor
final class LoopingServiceTests: XCTestCase {
	private let service = DefaultLoopingService()

	/// Mono buffer of `count` frames where frame `i` holds the value `Float(i)`.
	/// Sample rate 1000 Hz → the ~12 ms fade is `min(12, loopFrames/4, tail)` frames.
	private func rampBuffer(count: Int, sampleRate: Double = 1000) -> AVAudioPCMBuffer {
		let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
		buffer.frameLength = AVAudioFrameCount(count)
		let channel = buffer.floatChannelData![0]
		for i in 0 ..< count {
			channel[i] = Float(i)
		}
		return buffer
	}

	func testSlicesTheRequestedLength() {
		let out = service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 10, endFrame: 50)
		XCTAssertNotNil(out)
		XCTAssertEqual(out?.frameLength, 40)
	}

	func testSeamStartsAtTheSampleFollowingTheLoopEnd() throws {
		// loop [10, 50): loopFrames 40, /4 = 10, tail 50 → fade = 10.
		// At i=0 the equal-power ramp is fully "post" weighted, so out[0] == source[end].
		let out = try XCTUnwrap(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 10, endFrame: 50))
		let head = try XCTUnwrap(out.floatChannelData?[0])
		XCTAssertEqual(head[0], 50, accuracy: 1e-3) // source[50], continuous with source[49]
	}

	func testTailPastTheFadeIsUntouchedLoopContent() throws {
		// Only frames [0, fade) are blended; the rest is the raw memcpy'd slice.
		let out = try XCTUnwrap(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 10, endFrame: 50))
		let data = try XCTUnwrap(out.floatChannelData?[0])
		XCTAssertEqual(data[10], 20, accuracy: 1e-6) // fade end → source[10 + 10]
		XCTAssertEqual(data[39], 49, accuracy: 1e-6) // last frame → source[10 + 39]
	}

	func testNoCrossfadeWhenLoopEndsAtSourceEnd() throws {
		// No frames exist after the loop end, so the fade is 0 and the head is the
		// raw slice: out[0] == source[start].
		let out = try XCTUnwrap(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 60, endFrame: 100))
		XCTAssertEqual(out.frameLength, 40)
		XCTAssertEqual(try XCTUnwrap(out.floatChannelData?[0][0]), 60, accuracy: 1e-6)
	}

	func testInvalidRangesReturnNil() {
		let source = rampBuffer(count: 100)
		XCTAssertNil(service.makeLoopBuffer(from: source, startFrame: 50, endFrame: 50)) // empty
		XCTAssertNil(service.makeLoopBuffer(from: source, startFrame: 80, endFrame: 20)) // end < start
	}

	func testOutOfBoundsRangeIsClampedToTheSource() throws {
		// start clamps up to 0, end clamps down to totalFrames (100).
		let out = try XCTUnwrap(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: -5, endFrame: 200))
		XCTAssertEqual(out.frameLength, 100)
		XCTAssertEqual(try XCTUnwrap(out.floatChannelData?[0][0]), 0, accuracy: 1e-6) // ends at source end → no fade
	}
}
