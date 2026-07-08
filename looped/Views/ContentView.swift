//
//  ContentView.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AppKit
import SwiftUI

struct ContentView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	var body: some View {
		VStack(spacing: 20) {
			header
			WaveformDisplayView()
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

			if audioPlayer.audioURL != nil {
				HStack {
					Text(TimeFormatter.mmss(audioPlayer.currentTime)).padding()
					Text(TimeFormatter.mmss(audioPlayer.duration)).padding()
					Text(String(format: "%.2f", audioPlayer.getProgressInPercent())).padding()
					Text(String(format: "%.2fx", audioPlayer.rate)).padding()
				}
			}
		}
	}
}
