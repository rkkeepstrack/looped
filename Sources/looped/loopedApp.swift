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
	@StateObject private var player: PlayerViewModel
	@StateObject private var library: LibraryViewModel
	@StateObject private var waveform = WaveformViewModel(service: DefaultWaveformService())

	init() {
		let player = PlayerViewModel(
			playback: AVPlaybackService(),
			files: DefaultAudioFileService(),
			looping: DefaultLoopingService()
		)
		_player = StateObject(wrappedValue: player)
		_library = StateObject(wrappedValue: LibraryViewModel(player: player))
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(player)
				.environmentObject(library)
				.environmentObject(waveform)
				.frame(minWidth: 1024, minHeight: 800)
				.background(Theme.background)
				.preferredColorScheme(.dark)
		}
	}
}
