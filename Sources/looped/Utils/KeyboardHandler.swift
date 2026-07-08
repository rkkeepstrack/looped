//
//  KeyboardHandler.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AppKit
import SwiftUI

struct KeyboardHandler: NSViewRepresentable {
	@ObservedObject var audioPlayer: PlayerViewModel

	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
			handleKey(event: event)
			return event
		}
		context.coordinator.eventMonitor = monitor
		return view
	}

	func updateNSView(_: NSView, context _: Context) {}

	func handleKey(event: NSEvent) {
		switch event.charactersIgnoringModifiers?.lowercased() {
		case " ": audioPlayer.togglePlayPause()
		default: break
		}
	}

	func dismantleNSView(_: NSView, coordinator: Coordinator) {
		if let monitor = coordinator.eventMonitor { NSEvent.removeMonitor(monitor) }
	}

	class Coordinator { var eventMonitor: Any? }
	func makeCoordinator() -> Coordinator {
		Coordinator()
	}
}
