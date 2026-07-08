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
import Testing

struct LoopingServiceTests {
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

	@Test func slicesTheRequestedLength() {
		let out = service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 10, endFrame: 50)
		#expect(out != nil)
		#expect(out?.frameLength == 40)
	}

	@Test func seamStartsAtTheSampleFollowingTheLoopEnd() throws {
		// loop [10, 50): loopFrames 40, /4 = 10, tail 50 → fade = 10.
		// At i=0 the equal-power ramp is fully "post" weighted, so out[0] == source[end].
		let out = try #require(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 10, endFrame: 50))
		let head = try #require(out.floatChannelData?[0])
		#expect(abs(head[0] - 50) <= 1e-3) // source[50], continuous with source[49]
	}

	@Test func tailPastTheFadeIsUntouchedLoopContent() throws {
		// Only frames [0, fade) are blended; the rest is the raw memcpy'd slice.
		let out = try #require(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 10, endFrame: 50))
		let data = try #require(out.floatChannelData?[0])
		#expect(data[10] == 20) // fade end → source[10 + 10]
		#expect(data[39] == 49) // last frame → source[10 + 39]
	}

	@Test func noCrossfadeWhenLoopEndsAtSourceEnd() throws {
		// No frames exist after the loop end, so the fade is 0 and the head is the
		// raw slice: out[0] == source[start].
		let out = try #require(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: 60, endFrame: 100))
		#expect(out.frameLength == 40)
		#expect(try #require(out.floatChannelData?[0][0]) == 60)
	}

	@Test func invalidRangesReturnNil() {
		let source = rampBuffer(count: 100)
		#expect(service.makeLoopBuffer(from: source, startFrame: 50, endFrame: 50) == nil) // empty
		#expect(service.makeLoopBuffer(from: source, startFrame: 80, endFrame: 20) == nil) // end < start
	}

	@Test func outOfBoundsRangeIsClampedToTheSource() throws {
		// start clamps up to 0, end clamps down to totalFrames (100).
		let out = try #require(service.makeLoopBuffer(from: rampBuffer(count: 100), startFrame: -5, endFrame: 200))
		#expect(out.frameLength == 100)
		#expect(try #require(out.floatChannelData?[0][0]) == 0) // ends at source end → no fade
	}
}
