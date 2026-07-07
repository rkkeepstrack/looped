//
//  ContentView.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AppKit
import SwiftUI
internal import AVFAudio

struct ContentView: View {
	@EnvironmentObject var audioPlayer: AudioEngineController
	@EnvironmentObject var offsetCalculator: OffsetCalculator

	let formatter = DateComponentsFormatter()
	
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
	
	// MARK: Utils
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
