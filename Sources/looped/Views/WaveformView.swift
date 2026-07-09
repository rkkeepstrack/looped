//
//  WaveformView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import AppKit
import DSWaveformImage
import SwiftUI

struct WaveformDisplayView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	/// Noise-floor cutoff (dB) for analysis — higher (less negative) favors peaks.
	private let waveformNoiseFloor: Float = -35

	var body: some View {
		ZStack {
			if let url = audioPlayer.audioURL {
				GeometryReader { geo in
					// `.animation` re-evaluates per display frame while playing, so the pan
					// advances with the display clock instead of the coarser 0.03 s state
					// timer (whose beat against the refresh rate made the scroll judder).
					TimelineView(.animation(minimumInterval: nil, paused: !audioPlayer.isPlaying)) { _ in
						let width = geo.size.width
						let height = geo.size.height
						let time = audioPlayer.livePlaybackTime()
						// A bucket-aligned chunk around the playhead — translated smoothly
						// via `offset`, so only a viewport-sized slice is ever drawn.
						let win = offsetCalculator.window(playbackTime: time)

						ZStack {
							// Panning chunk: waveform + loop markers, offset under the iterator.
							ZStack {
								SyncWaveformCanvas(samples: win.samples, configuration: configuration(color: Theme.waveformUpcoming))
									.frame(width: win.width, height: height)
								SyncWaveformCanvas(samples: win.samples, configuration: configuration(color: Theme.waveformPlayed))
									.frame(width: win.width, height: height)
									.mask(alignment: .leading) { Rectangle().frame(width: win.playheadX) }

								// Scrub highlight (bug-fixes.md #1): while scrubbing, tint the span
								// between the played edge and the scrub cursor (the viewport center)
								// light blue — over the upcoming gray when scrubbing forward, over
								// the played orange when scrubbing backwards. Fades out naturally as
								// the snap-back shrinks the span to zero.
								if offsetCalculator.isScrolling {
									let centerTime = offsetCalculator.centerTime(playbackTime: time)
									let centerX = offsetCalculator.chunkX(forTime: centerTime, chunkStartSample: win.chunkStartSample)
									let lower = min(win.playheadX, centerX)
									let upper = max(win.playheadX, centerX)
									SyncWaveformCanvas(samples: win.samples, configuration: configuration(color: Theme.waveformScrub))
										.frame(width: win.width, height: height)
										.mask(alignment: .leading) {
											Rectangle()
												.frame(width: upper - lower)
												.offset(x: lower)
										}
								}

								loopOverlay(win: win, height: height)
							}
							.frame(width: win.width, height: height)
							.offset(x: win.offset)

							// Fixed center iterator (playhead).
							Rectangle()
								.fill(Theme.iterator)
								.frame(width: 2)
						}
						.clipped()
						.onAppear {
							offsetCalculator.waveformWidth = width
							prepareWaveform(url: url)
						}
						.onChange(of: width) { _, newWidth in offsetCalculator.waveformWidth = newWidth }
						.onChange(of: audioPlayer.audioURL) { _, _ in prepareWaveform(url: audioPlayer.audioURL) }
						.onChange(of: audioPlayer.duration) { _, _ in prepareWaveform(url: audioPlayer.audioURL) }
					}
				}
			} else {
				Text("No audio file loaded")
					.foregroundStyle(Theme.textSecondary)
					.frame(maxWidth: .infinity, minHeight: 120)
			}

			// Transparent overlay capturing scroll / drag to scrub the timeline.
			ScrollObserverView(
				offset: Binding(
					get: { offsetCalculator.currentScrollOffset },
					set: { offsetCalculator.currentScrollOffset = $0 }
				),
				onScrollChange: { _ in
					offsetCalculator.onScrollChange()
				},
				onScrollEnd: {
					let target = offsetCalculator.scrolledTime(playbackTime: audioPlayer.currentTime)
					if audioPlayer.jumpTo(time: target) {
						// Seeked: the view is already at the target, snap immediately.
						offsetCalculator.endScrubImmediately()
					} else {
						// Loop / out-of-bounds: ease back to the live playhead.
						offsetCalculator.animateSnapBack()
					}
				}
			)
		}
	}

	// MARK: - Loop region + markers (positioned in chunk coordinates)

	@ViewBuilder
	private func loopOverlay(win: WaveformWindow, height: CGFloat) -> some View {
		let loopA = audioPlayer.loopStart.0
		let loopB = audioPlayer.loopEnd.0

		if let a = loopA, let b = loopB, b > a {
			let ax = offsetCalculator.chunkX(forTime: a, chunkStartSample: win.chunkStartSample)
			let bx = offsetCalculator.chunkX(forTime: b, chunkStartSample: win.chunkStartSample)
			Rectangle()
				.fill(Theme.loopRegion)
				.frame(width: max(0, bx - ax), height: height)
				.position(x: (ax + bx) / 2, y: height / 2)
		}

		if let a = loopA {
			let x = offsetCalculator.chunkX(forTime: a, chunkStartSample: win.chunkStartSample)
			if x >= 0, x <= win.width {
				loopMarker(label: "A", color: Theme.loopMarkerA, x: x, height: height)
			}
		}
		if let b = loopB {
			let x = offsetCalculator.chunkX(forTime: b, chunkStartSample: win.chunkStartSample)
			if x >= 0, x <= win.width {
				loopMarker(label: "B", color: Theme.loopMarkerB, x: x, height: height)
			}
		}
	}

	private func loopMarker(label: String, color: Color, x: CGFloat, height: CGFloat) -> some View {
		ZStack(alignment: .top) {
			Rectangle().fill(color).frame(width: 1.5, height: height)
			Text(label)
				.font(.caption2.weight(.bold))
				.foregroundStyle(Color.black)
				.padding(.horizontal, 5)
				.padding(.vertical, 1)
				.background(color, in: Capsule())
		}
		.frame(width: 1.5, height: height)
		.position(x: x, y: height / 2)
	}

	// MARK: - Helpers

	private func prepareWaveform(url: URL?) {
		guard let url else { return }
		offsetCalculator.prepare(url: url, duration: audioPlayer.duration ?? 0, noiseFloor: waveformNoiseFloor)
	}

	private func configuration(color: Color) -> Waveform.Configuration {
		Waveform.Configuration(
			style: .striped(.init(
				color: NSColor(color),
				width: offsetCalculator.barWidth,
				spacing: offsetCalculator.barSpacing,
				lineCap: .round
			)),
			scale: offsetCalculator.sampleScale,
			verticalScalingFactor: 0.9,
			shouldAntialias: true
		)
	}
}

// MARK: - Synchronous waveform canvas

/// A `WaveformLiveCanvas` equivalent that draws **synchronously** (`rendersAsynchronously:
/// false`). The windowed renderer re-slices the visible chunk almost every refresh tick and
/// leans on a compensating `.offset` to keep the motion smooth; DSWaveformImage's async canvas
/// presents its redraw a frame late, so the fresh slice lags the offset and the seam shimmers
/// at the reslice cadence (bug-fixes.md #5). Drawing on the render pass commits the slice and
/// the offset together, killing the flicker. Same `WaveformImageDrawer` call as the library
/// view; only the presentation timing differs.
private struct SyncWaveformCanvas: View {
	let samples: [Float]
	let configuration: Waveform.Configuration
	var renderer: WaveformRenderer = LinearWaveformRenderer()

	@StateObject private var drawer = WaveformImageDrawer()

	var body: some View {
		Canvas(rendersAsynchronously: false) { context, size in
			context.withCGContext { cgContext in
				drawer.draw(waveform: samples, on: cgContext, with: configuration.with(size: size), renderer: renderer)
			}
		}
	}
}
