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

	// MARK: - Peak morph

	@Test func peakMorphKeepsEndpointsAndExpandsLoudContrast() {
		// Inverted dB: 0 == loudest, 1 == silence — the endpoints must be fixed.
		let out = service.peakMorph(samples: [0.0, 1.0], exponent: 2.0)
		#expect(out == [0.0, 1.0])

		// γ = 2: a' = a², so loud pairs spread apart and quiet pairs squeeze.
		let loud = service.peakMorph(samples: [0.05, 0.10], exponent: 2.0)
		#expect(abs((loud[1] - loud[0]) - 0.0925) < 0.0001) // raw gap 0.05 → ~2×
		let quiet = service.peakMorph(samples: [0.80, 0.85], exponent: 2.0)
		#expect((quiet[1] - quiet[0]) < 0.05)
	}

	@Test func peakMorphClampsOutOfRangeSamples() {
		let out = service.peakMorph(samples: [-0.5, 1.5], exponent: 2.0)
		#expect(out == [0.0, 1.0])
	}

	@Test func peakMorphExponentOneIsIdentity() {
		let samples: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
		let out = service.peakMorph(samples: samples, exponent: 1.0)
		for (a, b) in zip(out, samples) {
			#expect(abs(a - b) < 0.0001)
		}
	}

	// MARK: - Overview downsampling

	@Test func overviewSamplesKeepPerBucketPeaks() {
		// Samples are inverted dB (1 == silence, 0 == loudest): the bucket min —
		// the loudest value — must survive.
		let samples: [Float] = [1.0, 0.2, 0.9, 1.0, 1.0, 0.5, 0.8, 1.0]
		let out = service.overviewSamples(samples: samples, targetCount: 2)
		#expect(out == [0.2, 0.5])
	}

	@Test func overviewSamplesPassThroughWhenAlreadySmall() {
		let samples: [Float] = [0.1, 0.2, 0.3]
		#expect(service.overviewSamples(samples: samples, targetCount: 10) == samples)
	}

	@Test func overviewSamplesEdgeCases() {
		#expect(service.overviewSamples(samples: [], targetCount: 10) == [])
		#expect(service.overviewSamples(samples: [0.5, 0.6], targetCount: 0) == [])
	}

	@Test func overviewSamplesCoverEverySourceSample() {
		// Uneven division (10 → 3): the buckets must tile the array with no gaps,
		// so a single loud spike is caught wherever it sits.
		for spike in 0 ..< 10 {
			var samples = [Float](repeating: 1.0, count: 10)
			samples[spike] = 0.0
			let out = service.overviewSamples(samples: samples, targetCount: 3)
			#expect(out.count == 3)
			#expect(out.contains(0.0), "spike at \(spike) lost in downsampling")
		}
	}

	// MARK: - Overview mapper (strip pixels ↔ song time)

	@Test func overviewMapperMapsTimeToXAndBack() {
		let mapper = OverviewMapper(stripWidth: 200, duration: 100)
		#expect(mapper.x(forTime: 0) == 0)
		#expect(mapper.x(forTime: 50) == 100)
		#expect(mapper.x(forTime: 100) == 200)
		#expect(mapper.time(forX: 100) == 50)
	}

	@Test func overviewMapperClampsTimeToSongBounds() {
		let mapper = OverviewMapper(stripWidth: 200, duration: 100)
		#expect(mapper.time(forX: -10) == 0)
		#expect(mapper.time(forX: 250) == 100)
	}

	@Test func overviewMapperZeroGeometryIsSafe() {
		#expect(OverviewMapper(stripWidth: 0, duration: 100).time(forX: 50) == 0)
		#expect(OverviewMapper(stripWidth: 200, duration: 0).x(forTime: 5) == 0)
		#expect(OverviewMapper(stripWidth: 200, duration: 0).box(centerTime: 0, visibleSeconds: 1).width == 0)
	}

	@Test func overviewMapperBoxCentersTheVisibleWindow() {
		// 100 s song on 200 pt: 10 visible seconds centered at 50 → [45, 55] s → x 90, width 20.
		let mapper = OverviewMapper(stripWidth: 200, duration: 100)
		let box = mapper.box(centerTime: 50, visibleSeconds: 10)
		#expect(box.x == 90)
		#expect(abs(box.width - 20) < 0.0001)
	}

	@Test func overviewMapperBoxShrinksAtTheSongEdges() {
		let mapper = OverviewMapper(stripWidth: 200, duration: 100)
		// Centered at t=0 only the forward half is inside the song.
		let start = mapper.box(centerTime: 0, visibleSeconds: 10)
		#expect(start.x == 0)
		#expect(start.width == 10)
		// Centered at the end, only the trailing half.
		let end = mapper.box(centerTime: 100, visibleSeconds: 10)
		#expect(end.x == 190)
		#expect(end.width == 10)
	}

	@Test func chunkXInvertsBackToPixels() {
		// At the center time, chunkX must equal the (unclamped) playhead position.
		#expect(service.chunkX(time: 1.0, layout: layout, chunkStartSample: 88) == 56)
		// A time before the chunk start is negative (marker off the leading edge) —
		// chunkX does not clamp, so loop markers can sit off-screen.
		#expect(service.chunkX(time: 0.0, layout: layout, chunkStartSample: 88) == -44)
	}
}
