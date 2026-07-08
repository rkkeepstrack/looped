//
//  WaveformViewModel.swift
//  looped
//
//  Observable state + gestures for the waveform. The windowing/analysis math lives
//  in `WaveformService` (pure, injected); this view-model holds the `@Published`
//  state (viewport width, scroll, analyzed samples), owns scrubbing + the snap-back
//  animation, and delegates the per-frame window computation to the service.
//

import Combine
import SwiftUI

final class WaveformViewModel: ObservableObject {
	// MARK: Layout / zoom

	/// Viewport width in points.
	@Published var waveformWidth: CGFloat = 0
	/// Horizontal zoom: waveform pixels per second of audio.
	var pixelsPerSecond: CGFloat = 100
	/// Analysis samples per display pixel (also the DSWaveformImage config scale).
	let sampleScale: CGFloat = 2
	/// Stripe geometry (drives both the bucket math and the render config).
	let barWidth: CGFloat = 2
	let barSpacing: CGFloat = 2

	// MARK: Scrubbing

	@Published var isScrolling: Bool = false
	@Published var currentScrollOffset: CGFloat = 0
	private var snapTimer: Timer?

	// MARK: Analyzed samples (whole song, loaded once per URL)

	@Published private(set) var samples: [Float] = []
	private var analyzedURL: URL?
	private var analysisTask: Task<Void, Never>?

	private let service: WaveformService

	init(service: WaveformService) {
		self.service = service
	}

	/// Geometry snapshot handed to the service for the pure math.
	private var layout: WaveformLayout {
		WaveformLayout(
			viewportWidth: waveformWidth,
			pixelsPerSecond: pixelsPerSecond,
			sampleScale: sampleScale,
			barWidth: barWidth,
			barSpacing: barSpacing
		)
	}

	// MARK: - Analysis

	/// Analyze the whole song once via the service. No-op if the URL is unchanged.
	func prepare(url: URL, duration: TimeInterval, noiseFloor: Float) {
		guard url != analyzedURL else { return }
		analyzedURL = url
		samples = []
		let samplesPerSecond = pixelsPerSecond * sampleScale
		analysisTask?.cancel()
		analysisTask = Task { [weak self] in
			guard let self else { return }
			let result = await service.analyze(url: url, duration: duration, noiseFloor: noiseFloor, samplesPerSecond: samplesPerSecond)
			await MainActor.run {
				guard self.analyzedURL == url else { return }
				self.samples = result
			}
		}
	}

	// MARK: - Window (delegated to the service)

	/// Time shown at the viewport center (the playhead). While scrubbing it's the
	/// live playhead shifted by the drag, so releasing eases back to live playback.
	func centerTime(playbackTime: TimeInterval) -> TimeInterval {
		isScrolling ? playbackTime - Double(currentScrollOffset / pixelsPerSecond) : playbackTime
	}

	func window(playbackTime: TimeInterval) -> WaveformWindow {
		service.window(samples: samples, layout: layout, centerTime: centerTime(playbackTime: playbackTime), playbackTime: playbackTime)
	}

	func chunkX(forTime time: TimeInterval, chunkStartSample: Double) -> CGFloat {
		service.chunkX(time: time, layout: layout, chunkStartSample: chunkStartSample)
	}

	// MARK: - Scrubbing

	func onScrollChange() {
		snapTimer?.invalidate()
		isScrolling = true
	}

	/// The center time to seek to when a scrub is released.
	func scrolledTime(playbackTime: TimeInterval) -> TimeInterval {
		playbackTime - Double(currentScrollOffset / pixelsPerSecond)
	}

	/// End a scrub immediately (used when the release seeked — the view is already
	/// at the target, so no animation is needed).
	func endScrubImmediately() {
		snapTimer?.invalidate()
		currentScrollOffset = 0
		isScrolling = false
	}

	/// Ease the scroll offset back to zero (converging on the live playhead) with a
	/// small per-frame decay. Driven manually because `withAnimation` would only
	/// tween view modifiers, not the re-sliced chunk — which desyncs the played edge.
	func animateSnapBack() {
		snapTimer?.invalidate()
		guard currentScrollOffset != 0 else { isScrolling = false
			return
		}

		let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
			guard let self else { timer.invalidate()
				return
			}
			currentScrollOffset *= 0.72 // ease-out
			if abs(currentScrollOffset) < 0.5 {
				currentScrollOffset = 0
				isScrolling = false
				timer.invalidate()
			}
		}
		RunLoop.main.add(timer, forMode: .common)
		snapTimer = timer
	}
}
