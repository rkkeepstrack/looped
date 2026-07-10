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
	@StateObject private var toasts: ToastCenter

	init() {
		// `.help` tooltips ride NSToolTip, whose initial delay is an app-wide
		// user default (milliseconds) — the system's is too slow for hint-bearing
		// controls like the playthrough-mode button. `register` doesn't persist.
		UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
		// AppKit appends Dictation / Emoji & Symbols to any menu titled "Edit"
		// at runtime, which would resurrect the Edit menu `AppCommands` removes
		// as a stub of just those system items.
		UserDefaults.standard.register(defaults: [
			"NSDisabledDictationMenuItem": true,
			"NSDisabledCharacterPaletteMenuItem": true,
		])
		// Single-window app: no window tabbing, and no AppKit-injected
		// "Show Tab Bar"/"Show All Tabs" cluttering the View menu.
		NSWindow.allowsAutomaticWindowTabbing = false

		let toasts = ToastCenter()
		let looping = DefaultLoopingService()
		let playback = AVPlaybackService(looping: looping)
		// A dead engine (init or a per-track rewire) surfaces as a toast — the
		// service itself stays UI-free. Strong capture on purpose: there's no
		// cycle (service → closure → center), and a weak one could drop the
		// held init-time failure delivered during construction.
		playback.onEngineStartFailure = { error in
			Task { @MainActor in toasts.report(error) }
		}
		let transport = PlaybackCoordinator(
			playback: playback,
			files: DefaultAudioFileService(),
			toasts: toasts
		)
		let player = PlayerViewModel(
			transport: transport,
			playback: playback,
			looping: looping
		)
		let library = LibraryViewModel(
			player: transport,
			dropped: DefaultDroppedFileService(),
			store: JSONLibraryStore(),
			toasts: toasts
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
		_toasts = StateObject(wrappedValue: toasts)
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.task { await library.restore() }
				.environmentObject(player)
				.environmentObject(library)
				.environmentObject(waveform)
				.environmentObject(toasts)
				.frame(minWidth: 1024, minHeight: 800)
				.background(Theme.background)
				.preferredColorScheme(.dark)
		}
		.commands {
			AppCommands(player: player, library: library)
		}
	}
}
