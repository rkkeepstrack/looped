//
//  OffsetCalculator.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI
internal import Combine

internal class OffsetCalculator: ObservableObject {
	@Published var isScrolling: Bool = false
	@Published var currentScrollOffset: CGFloat = 0
	@Published var waveformWidth: CGFloat = 0
	
	// internal state
	private var lastCalculatedOffsetBeforeScroll: Double = 0
	private var lastCalculatedTimeBeforeScroll: Double = 0
	private var lastProgressInPercentBeforeScroll: CGFloat = 0
	
	func calculateGradientWhileScrolling(progressInPercent: Double) -> Double {
		if !isScrolling {
			return progressInPercent
		}
		
		return self.lastProgressInPercentBeforeScroll - self.currentScrollOffset / self.waveformWidth
	}
	
	/**
	 Returns the Timestamp at the Iterator in the center.
	 */
	
	func calculateScrolledTimestamp(offset: CGFloat? = nil, duration: Double?) -> TimeInterval {
		let offset = -(offset ?? currentScrollOffset) // offset is inverted as the waveform moves to the left
		let duration = duration ?? 1
		let scrolledTime = duration * (offset / self.waveformWidth) + lastCalculatedTimeBeforeScroll
		return scrolledTime
	}
	
	func onScrollChange(progressInPercent: Double, currentTime: TimeInterval ) {
		if !isScrolling {
			self.lastCalculatedOffsetBeforeScroll = calculateOffsetForWaveform(progressInPercent: progressInPercent)
			self.lastCalculatedTimeBeforeScroll = currentTime
			self.lastProgressInPercentBeforeScroll = progressInPercent
		}
		isScrolling = true;
	}
	
	func calculateOffsetForWaveform(progressInPercent: Double) -> Double {
		/**
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
		
		let placeStartOfWaveformToCenter = self.waveformWidth / 2
		let progressInRelationToWidth = progressInPercent * self.waveformWidth
		let currentCalculatedOffset = placeStartOfWaveformToCenter - progressInRelationToWidth + currentScrollOffset
		return currentCalculatedOffset
	}
	
}
