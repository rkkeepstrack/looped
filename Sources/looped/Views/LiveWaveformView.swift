//
//  LiveWaveformView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import AppKit
import DSWaveformImage
import SwiftUI

/// The main waveform: a windowed slice around the playhead, re-rendered live
/// per display frame (vs the minimap's whole-song strip).
struct LiveWaveformView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	/// Noise-floor cutoff (dB) for analysis — higher (less negative) favors peaks.
	private let waveformNoiseFloor: Float = -35

	/// Vertical inset for the waveform itself — the loop markers, region, and
	/// playhead still span the full frame height.
	private let verticalInset: CGFloat = 48

	var body: some View {
		ZStack {
			if let url = audioPlayer.audioURL {
				GeometryReader { geo in
					// `.animation` re-evaluates per display frame while playing, so the
					// window (and the whole-stripe steps of the pan) tracks the display
					// clock instead of the coarser 0.03 s state timer (whose beat against
					// the refresh rate made the motion judder).
					TimelineView(.animation(minimumInterval: nil, paused: !audioPlayer.isPlaying)) { _ in
						let width = geo.size.width
						let height = geo.size.height
						let waveHeight = max(0, height - 2 * verticalInset)
						let time = audioPlayer.livePlaybackTime()
						// A bucket-aligned chunk around the playhead, translated via the
						// pitch-quantized `offset` (screen-fixed stripes — see
						// `WaveformService.window`), so only a viewport-sized slice is drawn.
						let win = offsetCalculator.window(playbackTime: time)

						ZStack {
							// Midline (bug-fixes.md #3): the axis the waveform mirrors around,
							// visible even through silence.
							Rectangle()
								.fill(Theme.waveformCenterline)
								.frame(width: width, height: 1)

							// Panning chunk: waveform + loop markers, offset under the iterator.
							ZStack {
								SyncWaveformCanvas(samples: win.samples, configuration: configuration(color: Theme.waveformUpcoming))
									.frame(width: win.width, height: waveHeight)
								SyncWaveformCanvas(samples: win.samples, configuration: configuration(color: Theme.waveformPlayed))
									.frame(width: win.width, height: waveHeight)
									.mask(alignment: .leading) { Rectangle().frame(width: win.playheadX) }

								// Scrub highlight: while scrubbing, tint the span between the played
								// edge and the scrub cursor (the viewport center) light blue — over
								// the upcoming gray when scrubbing forward, over the played orange
								// when scrubbing backwards. Fades out naturally as the snap-back
								// shrinks the span to zero. The cursor gets the pan residue so it
								// stays screen-smooth like the played edge.
								if offsetCalculator.isScrolling {
									let centerTime = offsetCalculator.centerTime(playbackTime: time)
									let centerX = offsetCalculator.chunkX(forTime: centerTime, chunkStartSample: win.chunkStartSample) + win.panResidue
									let lower = min(win.playheadX, centerX)
									let upper = max(win.playheadX, centerX)
									SyncWaveformCanvas(samples: win.samples, configuration: configuration(color: Theme.waveformScrub))
										.frame(width: win.width, height: waveHeight)
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
						// Pin to the *actual* frame: GeometryReader aligns its child
						// top-leading and the stack would size to the chunk (stored
						// width) — the playhead must center on the live width, or a
						// deferred shrink lands as a visible jump.
						.frame(width: width, height: height)
						.clipped()
						.onAppear {
							offsetCalculator.updateViewportWidth(width)
							prepareWaveform(url: url)
						}
						.onChange(of: width) { _, newWidth in offsetCalculator.updateViewportWidth(newWidth) }
						.onChange(of: audioPlayer.audioURL) { _, _ in prepareWaveform(url: audioPlayer.audioURL) }
						.onChange(of: audioPlayer.duration) { _, _ in prepareWaveform(url: audioPlayer.audioURL) }
					}
				}
			} else {
				EmptyStateView()
			}

			// Decode-in-flight spinner (double-clicking a library track).
			if audioPlayer.isLoadingTrack {
				ProgressView()
					.controlSize(.large)
					.tint(Theme.accent)
			}
		}
		// Transparent overlay capturing scroll / drag to scrub the timeline.
		.observeScrolling(
			offset: Binding(
				get: { offsetCalculator.currentScrollOffset },
				set: { offsetCalculator.currentScrollOffset = $0 }
			),
			onChange: { _ in
				offsetCalculator.onScrollChange(playbackTime: audioPlayer.livePlaybackTime())
			},
			onEnd: {
				// A gesture that never scrubbed (e.g. the lift of a glide-stopping
				// touch) has nothing to seek — the glide's own end already did.
				guard offsetCalculator.isScrolling else { return }
				let target = offsetCalculator.scrolledTime(playbackTime: audioPlayer.livePlaybackTime())
				if audioPlayer.jumpTo(time: target) {
					// Seeked: the view is already at the target, snap immediately.
					offsetCalculator.endScrubImmediately()
				} else {
					// Loop / out-of-bounds: ease back to the live playhead.
					offsetCalculator.animateSnapBack(playbackTime: audioPlayer.livePlaybackTime())
				}
			}
		)
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
				.foregroundStyle(.black)
				.frame(width: 16, height: 16)
				.background(color, in: Circle())
				// The enclosing frame is the 1.5 pt marker line — without this
				// the proposed width truncates the label to an empty badge.
				.fixedSize()
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
