//
//  ControlsView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI

struct ControlsView: View {
	@EnvironmentObject var audioPlayer: AudioEngineController
	@EnvironmentObject var offsetCalculator: OffsetCalculator
	
	@State private var rateSliderPosition: Double = 0.5 // normalized 0…1
	@State private var volumeSliderPosition: Float = 0.5
	
	var body: some View {
		VStack {
			HStack {
				Button(action: {audioPlayer.togglePlayPause()} ) {
					audioPlayer.isPlaying ? Image(systemName: "pause.fill"): Image(systemName: "play.fill")
				}
				Button(action: {
					audioPlayer.stop()
					offsetCalculator.currentScrollOffset = 0
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
}
