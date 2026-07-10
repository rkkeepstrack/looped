//
//  WaveformService.swift
//  looped
//
//  Pure waveform computation (no SwiftUI, no state): analyzes a whole song into an
//  amplitude sample array, and — for a given playhead + layout — computes the
//  bucket-aligned "window" (the viewport-sized slice around the playhead, its
//  offset, and the played-edge). The view-model owns the observable state and
//  gestures; this service owns the math, so it's trivially unit-testable.
//

import CoreGraphics
import DSWaveformImage
import Foundation

/// Geometry inputs for the windowing math.
struct WaveformLayout {
	var viewportWidth: CGFloat
	var pixelsPerSecond: CGFloat
	/// Analysis samples per display pixel (also the DSWaveformImage config scale).
	var sampleScale: CGFloat
	var barWidth: CGFloat
	var barSpacing: CGFloat

	/// Samples per second stored in the analyzed array.
	var sampleRate: CGFloat {
		pixelsPerSecond * sampleScale
	}

	/// One stripe occupies this many samples (`(width + spacing) × scale`).
	var stripeBucket: Int {
		max(1, Int((barWidth + barSpacing) * sampleScale))
	}
}

/// A rendered slice: the chunk samples, its width, the offset that positions it
/// under the fixed center iterator, and the playhead's x within the chunk.
struct WaveformWindow {
	var samples: [Float]
	var width: CGFloat
	var offset: CGFloat
	var playheadX: CGFloat
	var chunkStartSample: Double
}

/// Pure song-time ↔ strip-pixel mapping for the full-track overview (minimap).
/// The strip shows the whole song across its width; the box is the big
/// waveform's visible window intersected with the song bounds.
struct OverviewMapper {
	var stripWidth: CGFloat
	var duration: TimeInterval

	func x(forTime time: TimeInterval) -> CGFloat {
		guard duration > 0 else { return 0 }
		return CGFloat(time / duration) * stripWidth
	}

	func time(forX x: CGFloat) -> TimeInterval {
		guard stripWidth > 0 else { return 0 }
		let t = TimeInterval(x / stripWidth) * duration
		return min(max(0, t), duration)
	}

	/// The visible-window box in strip coordinates: `visibleSeconds` centered on
	/// `centerTime`, intersected with the song — shrinks at the edges rather than
	/// hanging past the strip.
	func box(centerTime: TimeInterval, visibleSeconds: TimeInterval) -> (x: CGFloat, width: CGFloat) {
		guard duration > 0 else { return (0, 0) }
		let start = max(0, min(centerTime - visibleSeconds / 2, duration))
		let end = max(0, min(centerTime + visibleSeconds / 2, duration))
		let startX = x(forTime: start)
		return (startX, x(forTime: end) - startX)
	}
}

protocol WaveformService: Sendable {
	/// Analyze the whole song into an amplitude envelope (off the main thread).
	func analyze(url: URL, duration: TimeInterval, noiseFloor: Float, samplesPerSecond: CGFloat) async -> [Float]

	/// The bucket-aligned window around `centerTime`. Recomputed each frame; the
	/// bucket snapping + `offset` keep the motion smooth and the peaks stable.
	func window(samples: [Float], layout: WaveformLayout, centerTime: TimeInterval, playbackTime: TimeInterval) -> WaveformWindow

	/// x of a song time within a chunk (for loop markers/region).
	func chunkX(time: TimeInterval, layout: WaveformLayout, chunkStartSample: Double) -> CGFloat

	/// Expand contrast between loud values (a power curve on the linear-ized
	/// amplitude) so louder/quieter parts stay distinguishable inside evenly
	/// loud sections — the loop-point-hunting view. Pure; applied once per
	/// analysis, not per frame.
	func peakMorph(samples: [Float], exponent: Float) -> [Float]

	/// Downsample the whole-song envelope to `targetCount` samples for the
	/// overview strip — per-bucket **min** (samples are inverted dB: 1 == silence,
	/// 0 == loudest), so peaks survive the reduction. No second decode.
	func overviewSamples(samples: [Float], targetCount: Int) -> [Float]
}

struct DefaultWaveformService: WaveformService {
	func analyze(url: URL, duration: TimeInterval, noiseFloor: Float, samplesPerSecond: CGFloat) async -> [Float] {
		let count = max(1, Int(CGFloat(duration) * samplesPerSecond))
		var analyzer = WaveformAnalyzer()
		analyzer.noiseFloorDecibelCutoff = noiseFloor
		return (try? await analyzer.samples(fromAudioAt: url, count: count)) ?? []
	}

	func window(samples: [Float], layout: WaveformLayout, centerTime: TimeInterval, playbackTime: TimeInterval) -> WaveformWindow {
		let bucket = layout.stripeBucket
		let viewportSamples = max(1, Int(layout.viewportWidth * layout.sampleScale))
		let chunkCount = viewportSamples + 2 * bucket // slack for the translate
		let width = CGFloat(chunkCount) / layout.sampleScale

		let centerSample = centerTime * Double(layout.sampleRate)
		let idealStart = centerSample - Double(chunkCount) / 2
		// Snap the chunk start down to a whole stripe bucket.
		let chunkStart = Int((idealStart / Double(bucket)).rounded(.down)) * bucket

		// Center is placed at the viewport centre; the chunk is centered in the outer
		// stack (leading at (viewportWidth - width)/2), so offset shifts it from there.
		let centerLocalX = CGFloat(centerSample - Double(chunkStart)) / layout.sampleScale
		let offset = (layout.viewportWidth / 2 - centerLocalX) - (layout.viewportWidth - width) / 2

		let playSample = playbackTime * Double(layout.sampleRate)
		let playheadX = CGFloat(playSample - Double(chunkStart)) / layout.sampleScale

		var window = [Float](repeating: 1, count: chunkCount) // 1 == silence
		if !samples.isEmpty {
			for i in 0 ..< chunkCount {
				let idx = chunkStart + i
				if idx >= 0, idx < samples.count { window[i] = samples[idx] }
			}
		}

		return WaveformWindow(
			samples: window,
			width: width,
			offset: offset,
			playheadX: min(max(0, playheadX), width),
			chunkStartSample: Double(chunkStart)
		)
	}

	func chunkX(time: TimeInterval, layout: WaveformLayout, chunkStartSample: Double) -> CGFloat {
		CGFloat(time * Double(layout.sampleRate) - chunkStartSample) / layout.sampleScale
	}

	func peakMorph(samples: [Float], exponent: Float) -> [Float] {
		// Samples are inverted dB (1 == silence, 0 == loudest). In amplitude terms
		// a = 1 − s, the curve is a^γ: with γ > 1 its slope grows toward a = 1, so
		// differences between loud values stretch while the quiet floor compresses.
		samples.map { 1 - pow(1 - min(max($0, 0), 1), exponent) }
	}

	func overviewSamples(samples: [Float], targetCount: Int) -> [Float] {
		guard targetCount > 0, !samples.isEmpty else { return [] }
		guard samples.count > targetCount else { return samples }
		return (0 ..< targetCount).map { i in
			let start = i * samples.count / targetCount
			let end = max(start + 1, (i + 1) * samples.count / targetCount)
			return samples[start ..< min(end, samples.count)].min() ?? 1
		}
	}
}
