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

	/// Viewport width in points; committed via `updateViewportWidth`.
	@Published private(set) var waveformWidth: CGFloat = 0
	/// How long a shrink is deferred. Each width change reschedules, so this only
	/// needs to outlast one animation frame gap; the composition root sets it from
	/// `Theme.sidebarAnimationDuration` as a safe upper bound.
	var viewportShrinkDelay: TimeInterval = 0.33
	private var shrinkTimer: Timer?
	private var pendingShrinkWidth: CGFloat?
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
	/// Playback time latched when a scrub begins. While scrubbing, the viewport is
	/// anchored here (not the advancing playback time), so the view holds still and
	/// the played edge travels on — the user "holds" the audio while it runs away.
	private var scrubAnchorTime: TimeInterval?
	private var snapTimer: Timer?

	// MARK: Analyzed samples (whole song, loaded once per URL)

	@Published private(set) var samples: [Float] = []
	private var analyzedURL: URL?
	private var analysisTask: Task<Void, Never>?

	private let service: WaveformService

	init(service: WaveformService) {
		self.service = service
	}

	deinit {
		shrinkTimer?.invalidate()
		snapTimer?.invalidate()
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

	// MARK: - Viewport width

	/// Commit a viewport resize. Grows apply immediately (a too-narrow chunk leaves
	/// blank edges); shrinks wait for the layout to settle: the window math centers
	/// the playhead in the *actual* frame regardless of the stored width, so the
	/// oversized chunk is just clipped and rides the sidebar animation instead of
	/// re-slicing mid-flight (visible jump).
	func updateViewportWidth(_ newWidth: CGFloat) {
		shrinkTimer?.invalidate()
		pendingShrinkWidth = nil
		guard newWidth != waveformWidth else { return }
		if newWidth > waveformWidth {
			waveformWidth = newWidth
		} else {
			pendingShrinkWidth = newWidth
			let timer = Timer(timeInterval: viewportShrinkDelay, repeats: false) { [weak self] _ in
				self?.flushPendingShrink()
			}
			RunLoop.main.add(timer, forMode: .common)
			shrinkTimer = timer
		}
	}

	/// Apply a deferred shrink now (the timer's action; also the test hook — the
	/// timer itself needs a live run loop).
	func flushPendingShrink() {
		shrinkTimer?.invalidate()
		shrinkTimer = nil
		guard let width = pendingShrinkWidth else { return }
		pendingShrinkWidth = nil
		waveformWidth = width
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
	/// latched anchor shifted by the drag (frozen in song coordinates even though
	/// playback runs on); during snap-back the anchor is cleared so the decaying
	/// offset eases the view back onto the live playhead.
	func centerTime(playbackTime: TimeInterval) -> TimeInterval {
		isScrolling ? (scrubAnchorTime ?? playbackTime) - Double(currentScrollOffset / pixelsPerSecond) : playbackTime
	}

	func window(playbackTime: TimeInterval) -> WaveformWindow {
		service.window(samples: samples, layout: layout, centerTime: centerTime(playbackTime: playbackTime), playbackTime: playbackTime)
	}

	func chunkX(forTime time: TimeInterval, chunkStartSample: Double) -> CGFloat {
		service.chunkX(time: time, layout: layout, chunkStartSample: chunkStartSample)
	}

	// MARK: - Overview (minimap)

	/// Whole-song envelope downsampled for the overview strip.
	func overviewSamples(targetCount: Int) -> [Float] {
		service.overviewSamples(samples: samples, targetCount: targetCount)
	}

	/// Drag of the overview highlight box: a strip-pixel delta converted into the
	/// main waveform's scroll-offset scale — the box drag *is* a scrub (anchor
	/// latched, playback keeps running; the release seek/snap-back is the view's
	/// call, same as the big waveform). Dragging the box right moves the viewport
	/// forward, so the offset decreases.
	func overviewScrub(byStripDelta deltaX: CGFloat, stripWidth: CGFloat, duration: TimeInterval, playbackTime: TimeInterval) {
		guard stripWidth > 0, duration > 0 else { return }
		onScrollChange(playbackTime: playbackTime)
		currentScrollOffset -= deltaX * CGFloat(duration) / stripWidth * pixelsPerSecond
	}

	// MARK: - Scrubbing

	/// Called on every scroll/drag delta; latches the anchor on the first one.
	func onScrollChange(playbackTime: TimeInterval) {
		snapTimer?.invalidate()
		if !isScrolling { scrubAnchorTime = playbackTime }
		isScrolling = true
	}

	/// The center time to seek to when a scrub is released.
	func scrolledTime(playbackTime: TimeInterval) -> TimeInterval {
		(scrubAnchorTime ?? playbackTime) - Double(currentScrollOffset / pixelsPerSecond)
	}

	/// End a scrub immediately (used when the release seeked — the view is already
	/// at the target, so no animation is needed).
	func endScrubImmediately() {
		snapTimer?.invalidate()
		scrubAnchorTime = nil
		currentScrollOffset = 0
		isScrolling = false
	}

	/// Ease the scroll offset back to zero (converging on the live playhead) with a
	/// small per-frame decay. Driven manually because `withAnimation` would only
	/// tween view modifiers, not the re-sliced chunk — which desyncs the played edge.
	func animateSnapBack(playbackTime: TimeInterval) {
		snapTimer?.invalidate()
		// Rebase the offset from the frozen anchor onto the live playhead so the
		// view's center is unchanged at release, then decays onto live playback.
		if let anchor = scrubAnchorTime {
			currentScrollOffset += CGFloat(playbackTime - anchor) * pixelsPerSecond
			scrubAnchorTime = nil
		}
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
