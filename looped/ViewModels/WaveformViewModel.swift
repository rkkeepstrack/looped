//
//  WaveformViewModel.swift
//  looped
//
//  Presentation math for the waveform (was `OffsetCalculator`): maps playback
//  progress ↔ horizontal scroll offset so the waveform pans under a fixed center
//  iterator, and computes loop-point x-positions. The waveform is rendered
//  `zoom`× wider than the viewport (`contentWidth`) so it pans faster.
//

internal import Combine
import SwiftUI

final class WaveformViewModel: ObservableObject {
	@Published var isScrolling: Bool = false
	@Published var currentScrollOffset: CGFloat = 0
	/// Width of the visible viewport (set from the container's geometry). Used
	/// only for centering the playhead.
	@Published var waveformWidth: CGFloat = 0
	/// Horizontal zoom: the waveform is rendered `zoom` × wider than the viewport,
	/// so the whole song spans `zoom` screen-widths and pans faster. Higher = more
	/// zoomed in = faster horizontal scroll.
	@Published var zoom: CGFloat = 12

	/// Full rendered width of the waveform (the entire song), across which
	/// progress, loop points, and scrubbing are measured.
	var contentWidth: CGFloat {
		waveformWidth * zoom
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
