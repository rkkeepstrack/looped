//
//  MinimapView.swift
//  looped
//
//  Full-track waveform preview (minimap, plans/04): a fixed-height strip under the
//  main waveform showing the whole song, with a highlight box marking the big view's
//  visible window. Dragging the box scrubs the big waveform's viewport and seeks to
//  the dropped position on release (like the big view's scrub); clicking outside the
//  box seeks; clicking inside it is inert. Same highlight language as the big view:
//  played tint up to the playhead, scrub tint while scrubbing, loop region + thin
//  A/B lines.
//

import AppKit
import DSWaveformImage
import SwiftUI

struct MinimapView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	/// Whole-song envelope downsampled to the strip — recomputed on analysis/width
	/// changes only, not per display frame.
	@State private var overview: [Float] = []

	/// Box drag vs. click, decided at the first drag change by the start location.
	private enum DragMode {
		case idle
		/// Started inside the box: strip deltas scrub the viewport; `lastX` tracks
		/// the previous change so each update applies only the increment.
		case scrubbing(lastX: CGFloat)
		/// Started outside the box: a stationary release seeks, movement is inert.
		case pending(startX: CGFloat)
	}

	@State private var dragMode: DragMode = .idle

	var body: some View {
		GeometryReader { geo in
			ZStack {
				if let duration = audioPlayer.duration, duration > 0, !overview.isEmpty {
					strip(width: geo.size.width, height: geo.size.height, duration: duration)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.contentShape(Rectangle())
			.gesture(stripGesture(width: geo.size.width))
			.onAppear { refreshOverview(width: geo.size.width) }
			.onChange(of: geo.size.width) { _, newWidth in refreshOverview(width: newWidth) }
			.onChange(of: offsetCalculator.samples) { _, _ in refreshOverview(width: geo.size.width) }
		}
		.frame(height: Theme.overviewHeight)
		.background(Theme.surface)
	}

	// MARK: - Strip rendering

	private func strip(width: CGFloat, height: CGFloat, duration: TimeInterval) -> some View {
		TimelineView(.animation(minimumInterval: nil, paused: !audioPlayer.isPlaying)) { _ in
			let mapper = OverviewMapper(stripWidth: width, duration: duration)
			let time = audioPlayer.livePlaybackTime()
			let playedX = mapper.x(forTime: time)

			ZStack(alignment: .leading) {
				SyncWaveformCanvas(samples: overview, configuration: configuration(color: Theme.waveformUpcoming))
				SyncWaveformCanvas(samples: overview, configuration: configuration(color: Theme.overviewPlayed))
					.mask(alignment: .leading) { Rectangle().frame(width: max(0, playedX)) }

				// Scrub tint between the played edge and the scrub cursor, mirroring
				// the big view.
				if offsetCalculator.isScrolling {
					let centerX = mapper.x(forTime: offsetCalculator.centerTime(playbackTime: time))
					let lower = min(playedX, centerX)
					let upper = max(playedX, centerX)
					SyncWaveformCanvas(samples: overview, configuration: configuration(color: Theme.waveformScrub))
						.mask(alignment: .leading) {
							Rectangle()
								.frame(width: max(0, upper - lower))
								.offset(x: lower)
						}
				}

				loopOverlay(mapper: mapper, height: height)

				// The visible-window highlight box.
				let box = box(mapper: mapper, time: time)
				RoundedRectangle(cornerRadius: 4)
					.fill(Theme.overviewBoxFill)
					.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.overviewBoxStroke, lineWidth: 1))
					.frame(width: max(MinimapHelpers.minBoxWidth, box.width), height: height - 4)
					.offset(x: box.x)
			}
			.frame(width: width, height: height)
		}
	}

	@ViewBuilder
	private func loopOverlay(mapper: OverviewMapper, height: CGFloat) -> some View {
		let loopA = audioPlayer.loopStart.0
		let loopB = audioPlayer.loopEnd.0

		if let a = loopA, let b = loopB, b > a {
			let ax = mapper.x(forTime: a)
			Rectangle()
				.fill(Theme.loopRegion)
				.frame(width: max(0, mapper.x(forTime: b) - ax), height: height)
				.offset(x: ax)
		}
		if let a = loopA {
			Rectangle().fill(Theme.loopMarkerA).frame(width: 1, height: height).offset(x: mapper.x(forTime: a))
		}
		if let b = loopB {
			Rectangle().fill(Theme.loopMarkerB).frame(width: 1, height: height).offset(x: mapper.x(forTime: b))
		}
	}

	// MARK: - Gesture (box drag → scrub, outside click → seek, box click → inert)

	private func stripGesture(width: CGFloat) -> some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { value in
				guard let duration = audioPlayer.duration, duration > 0 else { return }
				switch dragMode {
				case .idle:
					let mapper = OverviewMapper(stripWidth: width, duration: duration)
					let box = box(mapper: mapper, time: audioPlayer.livePlaybackTime())
					if MinimapHelpers.boxContains(box: box, x: value.startLocation.x) {
						dragMode = .scrubbing(lastX: value.startLocation.x)
					} else {
						dragMode = .pending(startX: value.startLocation.x)
					}
				case let .scrubbing(lastX):
					offsetCalculator.overviewScrub(
						byStripDelta: value.location.x - lastX,
						stripWidth: width,
						duration: duration,
						playbackTime: audioPlayer.livePlaybackTime()
					)
					dragMode = .scrubbing(lastX: value.location.x)
				case .pending:
					break
				}
			}
			.onEnded { value in
				defer { dragMode = .idle }
				guard let duration = audioPlayer.duration, duration > 0 else { return }
				switch dragMode {
				case let .scrubbing(lastX):
					offsetCalculator.overviewScrub(
						byStripDelta: value.location.x - lastX,
						stripWidth: width,
						duration: duration,
						playbackTime: audioPlayer.livePlaybackTime()
					)
					// Release commits the drag — same as the big waveform's scrub
					// release: seek to the dropped position, or ease back when the
					// seek is refused (loop armed / out of bounds).
					let target = offsetCalculator.scrolledTime(playbackTime: audioPlayer.livePlaybackTime())
					if audioPlayer.jumpTo(time: target) {
						offsetCalculator.endScrubImmediately()
					} else {
						offsetCalculator.animateSnapBack(playbackTime: audioPlayer.livePlaybackTime())
					}
				case let .pending(startX):
					// A stationary release outside the box seeks to the clicked time;
					// a refused seek (loop armed) is deliberately inert here.
					if abs(value.translation.width) < 4, abs(value.translation.height) < 4 {
						let mapper = OverviewMapper(stripWidth: width, duration: duration)
						_ = audioPlayer.jumpTo(time: mapper.time(forX: startX))
					}
				case .idle:
					break
				}
			}
	}

	// MARK: - View-state helpers (read the view-models / @State)

	private func box(mapper: OverviewMapper, time: TimeInterval) -> (x: CGFloat, width: CGFloat) {
		let visibleSeconds = TimeInterval(offsetCalculator.waveformWidth / offsetCalculator.pixelsPerSecond)
		return mapper.box(centerTime: offsetCalculator.centerTime(playbackTime: time), visibleSeconds: visibleSeconds)
	}

	private func refreshOverview(width: CGFloat) {
		overview = offsetCalculator.overviewSamples(targetCount: Int(width * offsetCalculator.sampleScale))
	}

	private func configuration(color: Color) -> Waveform.Configuration {
		MinimapHelpers.configuration(color: color, scale: offsetCalculator.sampleScale)
	}
}

// MARK: - Stateless helpers

/// Pure minimap helpers namespaced in a caseless enum — no view/view-model state,
/// everything in via parameters.
private enum MinimapHelpers {
	/// Minimum rendered (and hit-testable) width of the highlight box, so it stays
	/// grabbable when the visible window shrinks at the song edges.
	static let minBoxWidth: CGFloat = 4

	static func boxContains(box: (x: CGFloat, width: CGFloat), x: CGFloat) -> Bool {
		x >= box.x && x <= box.x + max(minBoxWidth, box.width)
	}

	/// Filled envelope (unlike the big view's stripes) — denser reads better at
	/// strip height.
	static func configuration(color: Color, scale: CGFloat) -> Waveform.Configuration {
		Waveform.Configuration(
			style: .filled(NSColor(color)),
			scale: scale,
			verticalScalingFactor: 0.9,
			shouldAntialias: true
		)
	}
}
