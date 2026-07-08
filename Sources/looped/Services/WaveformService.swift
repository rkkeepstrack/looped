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

protocol WaveformService: Sendable {
	/// Analyze the whole song into an amplitude envelope (off the main thread).
	func analyze(url: URL, duration: TimeInterval, noiseFloor: Float, samplesPerSecond: CGFloat) async -> [Float]

	/// The bucket-aligned window around `centerTime`. Recomputed each frame; the
	/// bucket snapping + `offset` keep the motion smooth and the peaks stable.
	func window(samples: [Float], layout: WaveformLayout, centerTime: TimeInterval, playbackTime: TimeInterval) -> WaveformWindow

	/// x of a song time within a chunk (for loop markers/region).
	func chunkX(time: TimeInterval, layout: WaveformLayout, chunkStartSample: Double) -> CGFloat
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
}
