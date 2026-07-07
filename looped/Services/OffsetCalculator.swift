//
//  OffsetCalculator.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

internal import Combine
import SwiftUI

class OffsetCalculator: ObservableObject {
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

	func calculateGradientWhileScrolling(progressInPercent: Double) -> Double {
		if !isScrolling {
			return progressInPercent
		}

		return lastProgressInPercentBeforeScroll - currentScrollOffset / waveformWidth
	}

	/*
	 Returns the Timestamp at the Iterator in the center.
	 */

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
		/*
		 First, we have to move the Waveform so that the Iterator is right in the middle and the waveform next to it.
		 This happens by adding the offset waveformWidth / 2.

		 Next, we need to account for any movements that happen during scrolling, which is the scrollOffset.

		 Finally, the Waveform has to move gradually as the Audiofile progresses (it progresses by moving left = negatively)
		 This is done by getting the current percentage that has already played and then multiplying it by the total width of the waveform.

		 To suppress the gradually movement by progress when scrolling,  the lastCalculatedOffsetBeforeScroll is used in that case.
		 */
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
