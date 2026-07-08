//
//  ControlsView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI

struct ControlsView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	@State private var rateSliderPosition: Double = 0.5 // normalized 0…1
	@State private var volumeSliderPosition: Float = 0.5

	var body: some View {
		VStack {
			HStack {
				Button(action: { audioPlayer.togglePlayPause() }) {
					Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
				}
				Button(action: {
					audioPlayer.stop()
					offsetCalculator.currentScrollOffset = 0
				}) {
					Image(systemName: "stop.fill")
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
				Slider(value: $volumeSliderPosition, in: 0 ... 1, onEditingChanged: { _ in
					audioPlayer.updateVolume(volume: volumeSliderPosition)
				})
				.tint(.blue)
			}
			HStack {
				Button(action: { audioPlayer.setLoopStart(time: audioPlayer.currentTime) }) {
					Image(systemName: audioPlayer.loopStart.1 != nil ? "a.circle.fill" : "a.circle")
				}
				Button(action: { audioPlayer.setLoopEnd(time: audioPlayer.currentTime) }) {
					Image(systemName: audioPlayer.loopEnd.1 != nil ? "b.circle.fill" : "b.circle")
				}
				Button("Reset") {
					audioPlayer.setLoopStart(time: nil)
					audioPlayer.setLoopEnd(time: nil)
				}
			}
		}
	}
}
