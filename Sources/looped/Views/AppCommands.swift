//
//  AppCommands.swift
//  looped
//

import SwiftUI

/// The native menu bar. A separate `Commands` struct with `@ObservedObject`
/// view-models so the items (titles, checkmarks, enablement) stay live.
///
/// Shortcut ownership: the menu holds every equivalent shown here — including
/// the bare-key a/b/r — while space, tab, and ⌫/⌦ stay with the local key
/// monitor (`KeyboardShortcuts.swift`). Never bind a key in both places.
struct AppCommands: Commands {
	@ObservedObject var player: PlayerViewModel
	@ObservedObject var library: LibraryViewModel
	@AppStorage("sidebarOpen") private var sidebarOpen = true

	var body: some Commands {
		fileMenu
		removeEditMenu
		sidebarToggle
		playbackMenu
		loopMenu
	}

	// MARK: File — library actions

	private var fileMenu: some Commands {
		CommandGroup(replacing: .newItem) {
			Button("Import Files…") {
				Task { await library.openFilesAndLoad() }
			}
			.keyboardShortcut("o")

			Button("Import Folder…") {
				Task { await library.openFolder() }
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])

			Divider()

			Button("Remove Selected Track") {
				library.removeSelected()
			}
			.keyboardShortcut(.delete)
			.disabled(library.selectedTrackID == nil)
		}
	}

	// MARK: Edit — removed entirely

	/// Nothing in the app uses the responder chain, so every Edit item would be
	/// permanently dead. Emptying both groups hides the menu entirely; revisit
	/// if a future plan adds text fields (search etc.).
	@CommandsBuilder private var removeEditMenu: some Commands {
		CommandGroup(replacing: .undoRedo) {}
		CommandGroup(replacing: .pasteboard) {}
	}

	// MARK: View — sidebar

	private var sidebarToggle: some Commands {
		CommandGroup(replacing: .sidebar) {
			// Tab lives with the key monitor — AppKit hands a bare tab to the
			// focus loop before menu key-equivalent matching, so a `.tab`
			// equivalent here would render but never fire.
			Button(sidebarOpen ? "Hide Sidebar" : "Show Sidebar") {
				sidebarOpen.toggle()
			}
		}
	}

	// MARK: Playback — transport + parameters

	private var playbackMenu: some Commands {
		CommandMenu("Playback") {
			// Space lives with the key monitor — no equivalent here.
			Button(player.isPlaying ? "Pause" : "Play") {
				player.togglePlayPause()
			}
			.disabled(player.audioURL == nil)

			Button("Stop") {
				player.stop()
			}
			.keyboardShortcut(".")
			.disabled(player.audioURL == nil)

			Button("Next Track") {
				Task { await library.next() }
			}
			.keyboardShortcut(.rightArrow)
			.disabled(library.tracks.count < 2)

			Button("Previous Track") {
				Task { await library.previous() }
			}
			.keyboardShortcut(.leftArrow)
			.disabled(library.tracks.count < 2)

			Divider()

			Picker("When a Track Ends", selection: $player.playthroughMode) {
				Text("Loop This Track").tag(PlaythroughMode.loop)
				Text("Play the Next Track").tag(PlaythroughMode.advance)
				Text("Stop").tag(PlaythroughMode.stop)
			}
			.pickerStyle(.inline)

			Divider()

			parameterItems
		}
	}

	@ViewBuilder private var parameterItems: some View {
		Button("Volume Up") {
			player.stepVolume(by: 0.1)
		}
		.keyboardShortcut(.upArrow)
		.disabled(player.audioURL == nil)

		Button("Volume Down") {
			player.stepVolume(by: -0.1)
		}
		.keyboardShortcut(.downArrow)
		.disabled(player.audioURL == nil)

		Divider()

		// "+" matches the *character*, so on layouts where + is shifted (US)
		// these need the shift key too (⌘⇧=); SwiftUI can't express Safari's
		// hidden ⌘= alias. Accepted for the honest "⌘+" rendering.
		Button("Faster") {
			player.stepRate(bySemitones: 1)
		}
		.keyboardShortcut("+")
		.disabled(player.audioURL == nil)

		Button("Slower") {
			player.stepRate(bySemitones: -1)
		}
		.keyboardShortcut("-")
		.disabled(player.audioURL == nil)

		Button("Pitch Up") {
			player.stepPitch(bySemitones: 1)
		}
		.keyboardShortcut("+", modifiers: [.command, .option])
		.disabled(player.audioURL == nil || player.syncPitchAndRate)

		Button("Pitch Down") {
			player.stepPitch(bySemitones: -1)
		}
		.keyboardShortcut("-", modifiers: [.command, .option])
		.disabled(player.audioURL == nil || player.syncPitchAndRate)

		Button("Reset Speed & Pitch") {
			player.resetRateAndPitch()
		}
		.disabled(player.audioURL == nil)

		Divider()

		Toggle("Sync Pitch & Rate", isOn: Binding(
			get: { player.syncPitchAndRate },
			set: { player.updateSync($0) }
		))
		.keyboardShortcut("s", modifiers: [.command, .option])
		.disabled(player.audioURL == nil)
	}

	// MARK: Loop — A/B points

	private var loopMenu: some Commands {
		CommandMenu("Loop") {
			Button(player.loopStart.1 == nil ? "Set Loop Start at Playhead" : "Clear Loop Start") {
				player.toggleLoopStart()
			}
			.keyboardShortcut("a", modifiers: [])
			.disabled(player.audioURL == nil)

			Button(player.loopEnd.1 == nil ? "Set Loop End at Playhead" : "Clear Loop End") {
				player.toggleLoopEnd()
			}
			.keyboardShortcut("b", modifiers: [])
			.disabled(player.audioURL == nil)

			Button("Clear Loop Points") {
				player.clearLoopPoints()
			}
			.keyboardShortcut("r", modifiers: [])
			.disabled(player.loopStart.1 == nil && player.loopEnd.1 == nil)

			Divider()

			Button("Nudge Start Earlier") {
				player.nudgeLoopStart(by: -PlayerViewModel.loopNudgeStep)
			}
			.disabled(player.loopStart.1 == nil)

			Button("Nudge Start Later") {
				player.nudgeLoopStart(by: PlayerViewModel.loopNudgeStep)
			}
			.disabled(player.loopStart.1 == nil)

			Button("Nudge End Earlier") {
				player.nudgeLoopEnd(by: -PlayerViewModel.loopNudgeStep)
			}
			.disabled(player.loopEnd.1 == nil)

			Button("Nudge End Later") {
				player.nudgeLoopEnd(by: PlayerViewModel.loopNudgeStep)
			}
			.disabled(player.loopEnd.1 == nil)
		}
	}
}
