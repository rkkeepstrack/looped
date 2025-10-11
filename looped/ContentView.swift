//
//  ContentView.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import SwiftUI
import AppKit
import DSWaveformImageViews
internal import AVFAudio

struct ContentView: View {
	@ObservedObject var audioPlayer: AudioEngineController
    @State private var lastClickedTime = 0
	@State private var sliderPos: Double = 0.5 // normalized 0…1
	
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
				}
			}
		}
	}
	
	// MARK: Waveform
	private var waveform: some View {
		ZStack {
			if let url = audioPlayer.audioFile?.url {
				GeometryReader { geo in
					ZStack(alignment: .leading) {
						DSWaveformImageViews.WaveformView(audioURL: url) { waveformShape in
							waveformShape
								.fill(Color.purple)
						}
						
					}.gesture(
						DragGesture(minimumDistance: 0)
							.onEnded { value in
								let x = value.location.x
								let duration = audioPlayer.duration ?? 1
								let clickedTime = duration * (x / geo.size.width)
								lastClickedTime = Int(clickedTime)
								audioPlayer.jumpTo(time: clickedTime)
							}
					)
					Rectangle().fill(.yellow).frame(width:1).offset(x: calculateOffsetForIterator(width: geo.size.width))
				}
			} else {
				Text("No audio file loaded").frame(height: 120)
			}
		}
	}
	// MARK: Controls
	private var controls: some View {
		VStack {
			HStack {
				Button(audioPlayer.isPlaying ? "Pause" : "Play") {
					audioPlayer.togglePlayPause()
				}
				Button("Stop") {
					audioPlayer.stop()
				}
			}
			
			VStack {
				Slider(value: $sliderPos) { _ in
					audioPlayer.rate = Float(0.5 * pow(4, sliderPos)) // logarithmic scale to keep thumb in the middle
					audioPlayer.updateRate()
				}
				.tint(.blue)
				HStack {
					Button("Reset Playback Speed") {
						audioPlayer.rate = 1
						audioPlayer.updateRate()
						sliderPos = 0.5
					}
					Text(String(format: "Playback Speed: %.2fx", audioPlayer.rate))
				}
				Text("lastClickedTime: \(lastClickedTime)").foregroundColor(.secondary)
			}
		}
	}
	
    func calculateOffsetForIterator(width: CGFloat) -> Double {
        let progressInPercent = audioPlayer.currentTime / (audioPlayer.duration ?? 0)
        return progressInPercent * width
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

