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
	/// "a"/"b" toggle the loop points, "r" resets both.
	func keyboardShortcuts(player: PlayerViewModel, toggleSidebar: @escaping () -> Void) -> some View {
		background(KeyboardHandler(audioPlayer: player, onToggleSidebar: toggleSidebar))
	}
}

/// App-wide key monitor behind `keyboardShortcuts`. Handled keys are consumed
/// so they don't also drive the focus system (tab) or a focused control (space).
private struct KeyboardHandler: NSViewRepresentable {
	@ObservedObject var audioPlayer: PlayerViewModel
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
