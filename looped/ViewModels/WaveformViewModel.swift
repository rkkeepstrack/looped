//
//  WaveformViewModel.swift
//  looped
//
//  Presentation math for the waveform (was `OffsetCalculator`): maps playback
//  progress ↔ horizontal scroll offset so the waveform pans under a fixed center
//  iterator, and computes loop-point x-positions.
//
//  The render width (`contentWidth`) depends only on the *audio* (duration ×
//  `pixelsPerSecond`), NOT the viewport — so resizing the window or toggling the
//  sidebar only re-centers/pans (a cheap offset recalculation) and never forces
//  the waveform to re-analyze or repaint. `waveformWidth` is the live viewport
//  width, used solely to keep the playhead centered.
//

internal import Combine
import SwiftUI

final class WaveformViewModel: ObservableObject {
	@Published var isScrolling: Bool = false
	@Published var currentScrollOffset: CGFloat = 0
	/// Live viewport width — used only to center the playhead.
	@Published var waveformWidth: CGFloat = 0
	/// Song length in seconds; the render width derives from this.
	@Published var songDuration: TimeInterval = 0

	/// Horizontal scale: waveform pixels per second of audio. Higher = wider
	/// waveform = more zoom and faster horizontal scroll.
	var pixelsPerSecond: CGFloat = 100
	/// Cap so very long songs don't produce an enormous (slow) render.
	private let maxContentWidth: CGFloat = 12000

	/// Full rendered width of the waveform (the whole song). Depends only on the
	/// song, so it's constant across viewport changes → no repaint on resize.
	var contentWidth: CGFloat {
		min(CGFloat(songDuration) * pixelsPerSecond, maxContentWidth)
	}

	/// Called on appear and whenever the container width changes (centering only).
	func viewportWidthChanged(_ width: CGFloat) {
		waveformWidth = width
	}

	// internal state
	private var lastCalculatedOffsetBeforeScroll: Double = 0
	private var lastCalculatedTimeBeforeScroll: Double = 0
	private var lastProgressInPercentBeforeScroll: CGFloat = 0

	/// Returns the timestamp at the iterator in the center after scrolling.
	func calculateScrolledTimestamp(offset: CGFloat? = nil, duration: Double?) -> TimeInterval {
		let offset = -(offset ?? currentScrollOffset) // offset is inverted as the waveform moves to the left
		let duration = duration ?? 1
		return duration * (offset / contentWidth) + lastCalculatedTimeBeforeScroll
	}

	func onScrollChange(progressInPercent: Double, currentTime: TimeInterval) {
		if !isScrolling {
			lastCalculatedOffsetBeforeScroll = calculateOffsetForWaveform(progressInPercent: progressInPercent)
			lastCalculatedTimeBeforeScroll = currentTime
			lastProgressInPercentBeforeScroll = progressInPercent
		}
		isScrolling = true
	}

	func calculateOffsetForWaveform(progressInPercent: Double) -> Double {
		// Center the "now" position under the fixed iterator: place the start of the
		// waveform at the viewport centre (waveformWidth / 2), then shift left by how
		// far we've progressed through the full content width. During scrolling we
		// hold the pre-scroll offset and add the live scroll delta instead.
		if isScrolling {
			return lastCalculatedOffsetBeforeScroll + currentScrollOffset
		}

		let placeStartOfWaveformToCenter = waveformWidth / 2
		let progressInRelationToWidth = progressInPercent * contentWidth
		return placeStartOfWaveformToCenter - progressInRelationToWidth + currentScrollOffset
	}

	func calculateOffsetForLoopPoint(time: TimeInterval, duration: TimeInterval) -> Double {
		guard duration > 0 else { return 0 }
		let offsetInPercent = time / duration // length ratio in relation to total audio length
		return offsetInPercent * contentWidth // ratio in relation to total content width
	}
}
