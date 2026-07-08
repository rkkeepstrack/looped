//
//  WaveformServiceTests.swift
//  loopedTests
//
//  Unit tests for the pure windowing math in `DefaultWaveformService`. No audio
//  file is analyzed here — `analyze(url:…)` is real file I/O and belongs to a
//  manual/integration pass; the `window`/`chunkX` geometry is deterministic and
//  is exactly what these tests pin down.
//

@testable import looped
import XCTest

@MainActor
final class WaveformServiceTests: XCTestCase {
	private let service = DefaultWaveformService()

	/// The layout used throughout: 100 pt viewport, 100 px/s, scale 2, 2/2 bars.
	/// Derived constants (so the expectations below aren't magic numbers):
	///   sampleRate    = 100 * 2                = 200 samples/s
	///   stripeBucket  = Int((2 + 2) * 2)       = 8 samples
	///   viewportSamps = Int(100 * 2)           = 200
	///   chunkCount    = 200 + 2*8              = 216
	///   width         = 216 / 2               = 108 pt
	private var layout: WaveformLayout {
		WaveformLayout(viewportWidth: 100, pixelsPerSecond: 100, sampleScale: 2, barWidth: 2, barSpacing: 2)
	}

	func testLayoutDerivedConstants() {
		XCTAssertEqual(layout.sampleRate, 200, accuracy: 1e-9)
		XCTAssertEqual(layout.stripeBucket, 8)
	}

	func testWindowGeometryAtOneSecond() {
		let win = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 1.0)

		XCTAssertEqual(win.width, 108, accuracy: 1e-6)
		XCTAssertEqual(win.offset, -2, accuracy: 1e-6)
		XCTAssertEqual(win.playheadX, 56, accuracy: 1e-6)
		XCTAssertEqual(win.chunkStartSample, 88, accuracy: 1e-9)
		XCTAssertEqual(win.samples.count, 216)
	}

	func testEmptySamplesAreAllSilence() {
		let win = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 1.0)
		// 1.0 is the silence sentinel used by the service.
		XCTAssertTrue(win.samples.allSatisfy { $0 == 1.0 })
	}

	func testChunkStartIsAlwaysBucketAligned() {
		for center in [0.0, 0.37, 1.0, 5.2, 13.9, 42.0] {
			let win = service.window(samples: [], layout: layout, centerTime: center, playbackTime: center)
			XCTAssertEqual(Int(win.chunkStartSample) % layout.stripeBucket, 0,
			               "chunkStart \(win.chunkStartSample) not aligned to bucket \(layout.stripeBucket)")
		}
	}

	func testStartOfSongHasNegativeChunkStartAndStableWidth() {
		let win = service.window(samples: [], layout: layout, centerTime: 0.0, playbackTime: 0.0)
		// Center at t=0: the chunk extends before the song start, so its start is
		// negative — the out-of-range head is silence-padded, width is unchanged.
		XCTAssertLessThan(win.chunkStartSample, 0)
		XCTAssertEqual(Int(win.chunkStartSample) % layout.stripeBucket, 0)
		XCTAssertEqual(win.width, 108, accuracy: 1e-6)
	}

	func testSamplesAreCopiedAndSilencePaddedPastTheEnd() {
		// chunkStart = 88, chunkCount = 216 → reads samples[88 ..< 304].
		let samples = (0 ..< 300).map(Float.init)
		let win = service.window(samples: samples, layout: layout, centerTime: 1.0, playbackTime: 1.0)

		XCTAssertEqual(win.samples.count, 216)
		XCTAssertEqual(win.samples[0], 88, accuracy: 1e-6) // samples[88]
		XCTAssertEqual(win.samples[211], 299, accuracy: 1e-6) // samples[299] (last in range)
		XCTAssertEqual(win.samples[212], 1.0, accuracy: 1e-6) // idx 300 → silence
		XCTAssertEqual(win.samples[215], 1.0, accuracy: 1e-6) // idx 303 → silence
	}

	func testPlayheadIsClampedToTheChunk() {
		// Center held at 1.0 (chunkStart 88); playhead far behind / ahead of it.
		let behind = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 0.0)
		XCTAssertEqual(behind.playheadX, 0, accuracy: 1e-6) // (0 - 88)/2 = -44 → clamped to 0

		let ahead = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 10.0)
		XCTAssertEqual(ahead.playheadX, 108, accuracy: 1e-6) // (2000 - 88)/2 = 956 → clamped to width
	}

	func testChunkXInvertsBackToPixels() {
		// At the center time, chunkX must equal the (unclamped) playhead position.
		XCTAssertEqual(service.chunkX(time: 1.0, layout: layout, chunkStartSample: 88), 56, accuracy: 1e-6)
		// A time before the chunk start is negative (marker off the leading edge) —
		// chunkX does not clamp, so loop markers can sit off-screen.
		XCTAssertEqual(service.chunkX(time: 0.0, layout: layout, chunkStartSample: 88), -44, accuracy: 1e-6)
	}
}
