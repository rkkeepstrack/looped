//
//  loopedApp.swift
//  looped
//
//  Created by Raphael Kalinowsi on 28.09.25.
//

import SwiftUI

@main
struct loopedApp: App {
	/// Composition root: build the services and inject them into the view-models.
	@StateObject private var player = PlayerViewModel(
		playback: AVPlaybackService(),
		files: DefaultAudioFileService(),
		looping: DefaultLoopingService()
	)
	@StateObject private var waveform = WaveformViewModel()

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(player)
				.environmentObject(waveform)
				.frame(minWidth: 1024, minHeight: 800)
				.background(Theme.background)
				.preferredColorScheme(.dark)
		}
	}
}
