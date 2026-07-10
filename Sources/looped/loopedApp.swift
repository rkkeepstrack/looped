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
		// `.help` tooltips ride NSToolTip, whose initial delay is an app-wide
		// user default (milliseconds) — the system's is too slow for hint-bearing
		// controls like the playthrough-mode button. `register` doesn't persist.
		UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])

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
			dropped: DefaultDroppedFileService(),
			store: JSONLibraryStore()
		)
		// Advance mode: end-of-track → the library picks and plays the next track.
		// (The mode branching itself lives in PlayerViewModel.trackEnded.)
		// Weak: the player must not retain the library.
		player.onAdvanceToNextTrack = { [weak library] in
			Task { await library?.trackEnded() }
		}
		// Per-track slider state: the library stashes/applies it on track
		// switches; the values themselves live in the player VM.
		library.captureParameters = { [weak player] in
			player?.currentParameters ?? TrackParameters()
		}
		library.applyParameters = { [weak player] in
			player?.currentParameters = $0
		}
		_player = StateObject(wrappedValue: player)
		_library = StateObject(wrappedValue: library)
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.task { await library.restore() }
				.environmentObject(player)
				.environmentObject(library)
				.environmentObject(waveform)
				.frame(minWidth: 1024, minHeight: 800)
				.background(Theme.background)
				.preferredColorScheme(.dark)
		}
	}
}
