//
//  ContentView.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AppKit
import DSWaveformImage
import DSWaveformImageViews
import SwiftUI
internal import AVFAudio

struct ContentView: View {
	@ObservedObject var audioPlayer: AudioEngineController
	@State private var lastClickedTime = 0
	@State private var rateSliderPosition: Double = 0.5 // normalized 0…1
	@State private var volumeSliderPosition: Float = 0.5
	@State private var waveformWidth = CGFloat(0)
	
	@State private var currentScrollOffset: CGFloat = 0
	@State private var lastCalculatedOffsetBeforeScroll: Double = 0
	@State private var lastCalculatedTimeBeforeScroll: Double = 0
	@State private var lastProgressInPercentBeforeScroll: CGFloat = 0
	@State private var isScrolling: Bool = false
	
	let formatter = DateComponentsFormatter()
	
	var body: some View {
		VStack(spacing: 20) {
			header
			waveform
			controls
		}
		.padding()
		.frame(minWidth: 600, minHeight: 400)
		// Keyboard shortcuts
		.background(KeyboardHandler(audioPlayer: audioPlayer))
	}
	
	// MARK: Header
	
	private var header: some View {
		VStack {
			Button("Load Audio File") {
				Task {
					await audioPlayer.openFile()
				}
			}.buttonStyle(.borderedProminent)
			
			if let fileName = audioPlayer.currentFileName {
				Text("Loaded: \(fileName)")
			}
			
			if audioPlayer.audioFile?.url != nil {
				HStack {
					Text(String(formatDuration(time: audioPlayer.currentTime))).padding()
					Text(String(formatDuration(time: audioPlayer.duration))).padding()
					Text(String(format: "%.2f", audioPlayer.currentTime / (audioPlayer.duration ?? 0))).padding()
					Text("\(audioPlayer.timePitch.rate)").padding()
				}
			}
		}
	}
	
	// MARK: Waveform
	
	private var waveform: some View {
		ZStack {
			if let url = audioPlayer.audioFile?.url {
				GeometryReader { geo in
					ZStack {
						DSWaveformImageViews.WaveformView(audioURL: url) { waveformShape in
							waveformShape.fill(
								LinearGradient(
									stops: [
										Gradient.Stop(color: .red, location: 0),
										Gradient.Stop(color: .red, location: calculateGradientWhileScrolling()),
										Gradient.Stop(color: .blue, location: calculateGradientWhileScrolling() + 0.0001),
										Gradient.Stop(color: .blue, location: 1)
											 ],
									startPoint: .leading,
									endPoint: .trailing
								)
							)
						}.offset(x: calculateOffsetForWaveform())
						
						Rectangle().fill(.yellow).frame(width: 1)
					}.onAppear {
						waveformWidth = geo.size.width
					}
				}
			} else {
				Text("No audio file loaded").frame(height: 120)
			}
			ScrollCaptureView(
				offset: $currentScrollOffset,
				onScrollChange: { newOffset in
					onScrollChange(newOffset: newOffset)
				},
				onScrollEnd: { onScrollEnd() }
			)
		}
	}
	
	// MARK: Controls
	
	private var controls: some View {
		VStack {
			HStack {
				Button(action: {audioPlayer.togglePlayPause()} ) {
					audioPlayer.isPlaying ? Image(systemName: "pause.fill"): Image(systemName: "play.fill")
				}
				Button(action: {
					audioPlayer.stop()
					currentScrollOffset = 0
				}) {
					Image(systemName:"stop.fill")
				}
			}
			
			VStack {
				Slider(value: $rateSliderPosition) { _ in
					audioPlayer.rate = Float(0.5 * pow(4, rateSliderPosition)) // logarithmic scale to keep thumb in the middle
					audioPlayer.updateRate()
				}
				.tint(.blue)
				HStack {
					Button("Reset Playback Speed") {
						audioPlayer.rate = 1
						audioPlayer.updateRate()
						rateSliderPosition = 0.5
					}
					Text(String(format: "Playback Speed: %.2fx", audioPlayer.rate))
				}
				Slider(value: $volumeSliderPosition, in: 0...1, onEditingChanged: { _ in
					audioPlayer.updateVolume(volume: volumeSliderPosition)
				})
				.tint(.blue)
				
			}
			
		}
	}
	
	// MARK: Utils
	
	func onScrollEnd() {
		audioPlayer.jumpTo(time: calculateScrolledTimestamp())
		currentScrollOffset = 0
		isScrolling = false
	}
	
	func onScrollChange(newOffset _: CGFloat) {
		if !isScrolling {
			lastCalculatedOffsetBeforeScroll = calculateOffsetForWaveform()
			lastCalculatedTimeBeforeScroll = audioPlayer.currentTime
			lastProgressInPercentBeforeScroll = audioPlayer.getProgressInPercent()
		}
		isScrolling = true
	}
	
	func calculateOffsetForWaveform() -> Double {
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
		
		let placeStartOfWaveformToCenter = waveformWidth / 2
		let progressInRelationToWidth = audioPlayer.getProgressInPercent() * waveformWidth
		let currentCalculatedOffset = placeStartOfWaveformToCenter - progressInRelationToWidth + currentScrollOffset
		return currentCalculatedOffset
	}
	
	func calculateGradientWhileScrolling() -> CGFloat {
		let progressInPercent = audioPlayer.getProgressInPercent()
		if !isScrolling {
			return CGFloat(progressInPercent)
		}

		return CGFloat(lastProgressInPercentBeforeScroll - currentScrollOffset / waveformWidth)
	}
	
	/**
	 Returns the Timestamp at the Iterator in the center.
	 */
	func calculateScrolledTimestamp(offset: CGFloat? = nil) -> TimeInterval {
		let offset = -(offset ?? currentScrollOffset) // offset is inverted as the waveform moves to the left
		let duration = audioPlayer.getDuration() ?? 1
		let scrolledTime = duration * (offset / waveformWidth) + lastCalculatedTimeBeforeScroll
		return scrolledTime
	}
	
	func formatDuration(time: TimeInterval?) -> String {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.minute, .second]
		formatter.zeroFormattingBehavior = [.pad] // ensures 2:05 instead of 2:5
		if let safeTime = time {
			return formatter.string(from: safeTime) ?? "0:00"
		}
		return "0:00"
	}
}
