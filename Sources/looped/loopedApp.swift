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
		let playback = AVPlaybackService()
		let transport = PlaybackCoordinator(
			playback: playback,
			files: DefaultAudioFileService()
		)
		let player = PlayerViewModel(
			transport: transport,
			playback: playback,
			looping: DefaultLoopingService()
		)
		let library = LibraryViewModel(
			player: transport,
			dropped: DefaultDroppedFileService()
		)
		// End-of-track → the library picks and plays the next track (auto-advance).
		// Weak: the coordinator must not retain the library that retains it.
		transport.onTrackEnded = { [weak library] in
			Task { await library?.trackEnded() }
		}
		_player = StateObject(wrappedValue: player)
		_library = StateObject(wrappedValue: library)
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
