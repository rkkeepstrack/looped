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
import Testing

struct WaveformServiceTests {
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

	@Test func layoutDerivedConstants() {
		#expect(layout.sampleRate == 200)
		#expect(layout.stripeBucket == 8)
	}

	@Test func windowGeometryAtOneSecond() {
		let win = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 1.0)

		#expect(win.width == 108)
		#expect(win.offset == -2)
		#expect(win.playheadX == 56)
		#expect(win.chunkStartSample == 88)
		#expect(win.samples.count == 216)
	}

	@Test func emptySamplesAreAllSilence() {
		let win = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 1.0)
		// 1.0 is the silence sentinel used by the service.
		#expect(win.samples.allSatisfy { $0 == 1.0 })
	}

	@Test func chunkStartIsAlwaysBucketAligned() {
		for center in [0.0, 0.37, 1.0, 5.2, 13.9, 42.0] {
			let win = service.window(samples: [], layout: layout, centerTime: center, playbackTime: center)
			#expect(Int(win.chunkStartSample) % layout.stripeBucket == 0,
			        "chunkStart \(win.chunkStartSample) not aligned to bucket \(layout.stripeBucket)")
		}
	}

	@Test func startOfSongHasNegativeChunkStartAndStableWidth() {
		let win = service.window(samples: [], layout: layout, centerTime: 0.0, playbackTime: 0.0)
		// Center at t=0: the chunk extends before the song start, so its start is
		// negative — the out-of-range head is silence-padded, width is unchanged.
		#expect(win.chunkStartSample < 0)
		#expect(Int(win.chunkStartSample) % layout.stripeBucket == 0)
		#expect(win.width == 108)
	}

	@Test func samplesAreCopiedAndSilencePaddedPastTheEnd() {
		// chunkStart = 88, chunkCount = 216 → reads samples[88 ..< 304].
		let samples = (0 ..< 300).map(Float.init)
		let win = service.window(samples: samples, layout: layout, centerTime: 1.0, playbackTime: 1.0)

		#expect(win.samples.count == 216)
		#expect(win.samples[0] == 88) // samples[88]
		#expect(win.samples[211] == 299) // samples[299] (last in range)
		#expect(win.samples[212] == 1.0) // idx 300 → silence
		#expect(win.samples[215] == 1.0) // idx 303 → silence
	}

	@Test func playheadIsClampedToTheChunk() {
		// Center held at 1.0 (chunkStart 88); playhead far behind / ahead of it.
		let behind = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 0.0)
		#expect(behind.playheadX == 0) // (0 - 88)/2 = -44 → clamped to 0

		let ahead = service.window(samples: [], layout: layout, centerTime: 1.0, playbackTime: 10.0)
		#expect(ahead.playheadX == 108) // (2000 - 88)/2 = 956 → clamped to width
	}

	@Test func chunkXInvertsBackToPixels() {
		// At the center time, chunkX must equal the (unclamped) playhead position.
		#expect(service.chunkX(time: 1.0, layout: layout, chunkStartSample: 88) == 56)
		// A time before the chunk start is negative (marker off the leading edge) —
		// chunkX does not clamp, so loop markers can sit off-screen.
		#expect(service.chunkX(time: 0.0, layout: layout, chunkStartSample: 88) == -44)
	}
}
