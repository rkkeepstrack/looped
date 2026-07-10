//
//  KeyboardShortcuts.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AppKit
import SwiftUI

extension View {
	/// Installs the app-wide keyboard shortcuts: space play/pause, tab sidebar,
	/// "a"/"b" toggle the loop points, "r" resets both, ⌫/⌦ remove the
	/// selected library track.
	func keyboardShortcuts(
		player: PlayerViewModel,
		library: LibraryViewModel,
		toggleSidebar: @escaping () -> Void
	) -> some View {
		background(KeyboardHandler(audioPlayer: player, library: library, onToggleSidebar: toggleSidebar))
	}
}

/// App-wide key monitor behind `keyboardShortcuts`. Handled keys are consumed
/// so they don't also drive the focus system (tab) or a focused control (space).
private struct KeyboardHandler: NSViewRepresentable {
	@ObservedObject var audioPlayer: PlayerViewModel
	@ObservedObject var library: LibraryViewModel
	var onToggleSidebar: () -> Void

	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
			handleKey(event: event) ? nil : event
		}
		context.coordinator.eventMonitor = monitor
		return view
	}

	func updateNSView(_: NSView, context _: Context) {}

	/// Returns whether the event was handled (and should be swallowed).
	func handleKey(event: NSEvent) -> Bool {
		// Don't steal keys from modal panels (open/import dialogs) — the local
		// monitor sees their events too.
		guard NSApp.modalWindow == nil else { return false }
		// Leave modified keys (⌘A etc.) to the menu / focus system.
		guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
			return false
		}
		switch event.charactersIgnoringModifiers?.lowercased() {
		case " ":
			audioPlayer.togglePlayPause()
		case "\t":
			onToggleSidebar()
		case "a" where audioPlayer.audioURL != nil:
			audioPlayer.toggleLoopStart()
		case "b" where audioPlayer.audioURL != nil:
			audioPlayer.toggleLoopEnd()
		case "r" where audioPlayer.audioURL != nil:
			audioPlayer.clearLoopPoints()
		// Backspace (⌫, 0x7F) and forward delete (⌦, NSDeleteFunctionKey).
		case "\u{7F}", "\u{F728}":
			// Local NSEvent monitors fire on the main thread; the library VM is
			// main-actor-bound.
			return MainActor.assumeIsolated {
				guard library.selectedTrackID != nil else { return false }
				library.removeSelected()
				return true
			}
		default:
			return false
		}
		return true
	}

	func dismantleNSView(_: NSView, coordinator: Coordinator) {
		if let monitor = coordinator.eventMonitor { NSEvent.removeMonitor(monitor) }
	}

	class Coordinator { var eventMonitor: Any? }
	func makeCoordinator() -> Coordinator {
		Coordinator()
	}
}
