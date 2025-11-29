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
	@EnvironmentObject var audioPlayer: AudioEngineController
	@EnvironmentObject var offsetCalculator: OffsetCalculator
	
	// UI related States
	@State private var lastClickedTime = 0
	@State private var rateSliderPosition: Double = 0.5 // normalized 0…1
	@State private var volumeSliderPosition: Float = 0.5

	let formatter = DateComponentsFormatter()
	
	var body: some View {
		VStack(spacing: 20) {
			header
			waveform
			ControlsView()
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
										Gradient.Stop(color: .red, location: offsetCalculator.calculateGradientWhileScrolling(progressInPercent: audioPlayer.getProgressInPercent())),
										Gradient.Stop(color: .blue, location: offsetCalculator.calculateGradientWhileScrolling(progressInPercent: audioPlayer.getProgressInPercent()) + 0.0001),
										Gradient.Stop(color: .blue, location: 1)
											 ],
									startPoint: .leading,
									endPoint: .trailing
								)
							)
						}.offset(x: offsetCalculator.calculateOffsetForWaveform(progressInPercent: audioPlayer.getProgressInPercent()))
						
						Rectangle().fill(.yellow).frame(width: 1)
					}.onAppear {
						offsetCalculator.waveformWidth = geo.size.width
					}
				}
			} else {
				Text("No audio file loaded").frame(height: 120)
			}
			ScrollObserverView(
				offset: Binding(
					 get: { offsetCalculator.currentScrollOffset },
					 set: { offsetCalculator.currentScrollOffset = $0 }
				),
				onScrollChange: { _ in
					offsetCalculator.onScrollChange(progressInPercent: audioPlayer.getProgressInPercent(), currentTime: audioPlayer.currentTime)
				},
				onScrollEnd: { onScrollEnd() }
			)
		}
	}
	
	
	// MARK: Utils
	
	func onScrollEnd() {
		audioPlayer.jumpTo(time: offsetCalculator.calculateScrolledTimestamp(offset: offsetCalculator.currentScrollOffset, duration: audioPlayer.getDuration()))
		offsetCalculator.currentScrollOffset = 0
		offsetCalculator.isScrolling = false
	}
	
	func onScrollChange() {
		offsetCalculator.onScrollChange(progressInPercent: audioPlayer.getProgressInPercent(), currentTime: audioPlayer.currentTime)
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
